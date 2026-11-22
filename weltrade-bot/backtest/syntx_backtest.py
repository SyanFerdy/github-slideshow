#!/usr/bin/env python3
"""
Backtester pour SyntX Guardian (indices synthetiques Weltrade).

Reproduit les deux moteurs de l'Expert Advisor MT5 sur des donnees en barres
pour verifier, AVANT de risquer de l'argent, s'il existe un vrai avantage :

  - DRIFT : GainX / PainX. Trade dans le sens de la derive lente, contre les pics.
  - TREND : croisement d'EMA + filtre ADX, stop/objectif en ATR, trailing ATR.

Donnees : CSV exporte de MT5 (script ExportBars.mq5 fourni, ou Ctrl+U >
Barres > Exporter). Colonnes acceptees (format MT5) :
  <DATE> <TIME> <OPEN> <HIGH> <LOW> <CLOSE> [<TICKVOL> <VOL> <SPREAD>]
ou simplement : time,open,high,low,close[,spread]

Exemples :
  python syntx_backtest.py data/GainX_999_M1.csv --engine drift --spread 0.5
  python syntx_backtest.py data/FX_Vol_20_M1.csv --engine trend --optimize
  python syntx_backtest.py --simulate gainx --bars 200000 --engine drift

Modele d'execution (volontairement prudent) :
  - entree a l'ouverture de la barre suivante, spread paye a chaque trade ;
  - si SL et TP sont touches dans la meme barre -> on suppose le SL ;
  - quand un pic traverse le SL, le depassement est compte comme
    glissement (--spike-slippage, 1.0 par defaut = realiste).
"""
from __future__ import annotations

import argparse
import itertools
import math
import sys
from dataclasses import dataclass, field

import numpy as np
import pandas as pd


# --------------------------------------------------------------------------
# Chargement des donnees
# --------------------------------------------------------------------------
def load_csv(path: str) -> pd.DataFrame:
    with open(path, "r", encoding="utf-8-sig", errors="ignore") as fh:
        head = fh.readline()
    sep = "\t" if "\t" in head else ("," if "," in head else ";")
    df = pd.read_csv(path, sep=sep)
    df.columns = [c.strip().strip("<>").lower() for c in df.columns]

    if "date" in df.columns and "time" in df.columns:
        df["time"] = pd.to_datetime(df["date"].astype(str) + " " + df["time"].astype(str))
    elif "time" in df.columns:
        df["time"] = pd.to_datetime(df["time"])
    else:
        df["time"] = pd.RangeIndex(len(df))

    needed = ["open", "high", "low", "close"]
    missing = [c for c in needed if c not in df.columns]
    if missing:
        sys.exit(f"Colonnes manquantes dans {path} : {missing}")

    keep = ["time"] + needed + (["spread"] if "spread" in df.columns else [])
    return df[keep].dropna().reset_index(drop=True)


def simulate(kind: str, bars: int, ticks_per_bar: int = 60, spike_every: int = 999,
             seed: int = 7, edge: float = 0.0) -> pd.DataFrame:
    """Simule un indice type GainX/PainX (pics) ou FX Vol (marche aleatoire).

    Par defaut la simulation est *equitable* (esperance nulle) : le backtest
    doit alors sortir environ -spread par trade. C'est le test de controle
    de l'outil : si une strategie "gagne" sur des donnees equitables, le
    backtest est faux. `edge` ajoute un biais artificiel (pour verifier que
    l'outil le detecte).
    """
    rng = np.random.default_rng(seed)
    n = bars * ticks_per_bar
    noise = rng.normal(0.0, 0.05, n)
    if kind in ("gainx", "painx"):
        p = 1.0 / spike_every
        spike_mean = 8.0
        is_spike = rng.random(n) < p
        spikes = rng.exponential(spike_mean, n) * is_spike
        drift = p * spike_mean / (1 - p) * (1.0 + edge)   # fair if edge = 0
        # D'apres les descriptions trouvees : GainX monte lentement et chute
        # par pics, PainX baisse lentement et bondit par pics.
        sign = 1.0 if kind == "gainx" else -1.0
        steps = sign * (np.where(is_spike, -spikes, drift) + noise)
    else:
        steps = rng.normal(edge * 0.01, 0.15, n)
    price = 10000.0 + np.cumsum(steps)
    price = price.reshape(bars, ticks_per_bar)
    open_ = np.concatenate([[10000.0], price[:-1, -1]])
    df = pd.DataFrame({
        "time": pd.date_range("2025-01-01", periods=bars, freq="min"),
        "open": open_,
        "high": np.maximum(price.max(axis=1), open_),
        "low": np.minimum(price.min(axis=1), open_),
        "close": price[:, -1],
    })
    return df


# --------------------------------------------------------------------------
# Indicateurs
# --------------------------------------------------------------------------
def ema(s: pd.Series, n: int) -> pd.Series:
    return s.ewm(span=n, adjust=False).mean()


def atr(df: pd.DataFrame, n: int) -> pd.Series:
    pc = df["close"].shift()
    tr = pd.concat([df["high"] - df["low"], (df["high"] - pc).abs(), (df["low"] - pc).abs()], axis=1).max(axis=1)
    return tr.ewm(alpha=1 / n, adjust=False).mean()


def adx(df: pd.DataFrame, n: int) -> pd.Series:
    up = df["high"].diff()
    dn = -df["low"].diff()
    plus_dm = np.where((up > dn) & (up > 0), up, 0.0)
    minus_dm = np.where((dn > up) & (dn > 0), dn, 0.0)
    a = atr(df, n)
    pdi = 100 * pd.Series(plus_dm, index=df.index).ewm(alpha=1 / n, adjust=False).mean() / a
    mdi = 100 * pd.Series(minus_dm, index=df.index).ewm(alpha=1 / n, adjust=False).mean() / a
    dx = 100 * (pdi - mdi).abs() / (pdi + mdi).replace(0, np.nan)
    return dx.ewm(alpha=1 / n, adjust=False).mean().fillna(0)


# --------------------------------------------------------------------------
# Analyse des pics
# --------------------------------------------------------------------------
def spike_report(df: pd.DataFrame, mult: float) -> dict:
    body = df["close"] - df["open"]
    med = body.abs().median()
    is_spike = body.abs() >= mult * med
    idx = np.flatnonzero(is_spike.to_numpy())
    rep = {
        "bars": len(df),
        "median_body": med,
        "spikes": int(len(idx)),
        "spikes_up": int((body[is_spike] > 0).sum()),
        "spikes_down": int((body[is_spike] < 0).sum()),
        "avg_spike": float(body[is_spike].abs().mean()) if len(idx) else 0.0,
        "net_move": float(df["close"].iloc[-1] - df["open"].iloc[0]),
    }
    non_spike = body[~is_spike]
    rep["drift_per_bar"] = float(non_spike.mean())
    rep["spike_per_bar"] = float(body[is_spike].sum() / len(df))
    if len(idx) > 20:
        gaps = np.diff(idx)
        rep["avg_bars_between"] = float(gaps.mean())
        # Test d'absence de memoire : si les pics sont aleatoires (loi
        # geometrique), la probabilite d'un pic "bientot" n'augmente pas
        # avec le temps ecoule depuis le dernier. On compare la probabilite
        # conditionnelle avant et apres l'ecart median.
        m = np.median(gaps)
        early = (gaps <= m / 2).sum() / len(gaps)
        cond_late = ((gaps > m) & (gaps <= 1.5 * m)).sum() / max((gaps > m).sum(), 1)
        cond_early = early
        rep["hazard_early"] = float(cond_early)
        rep["hazard_late"] = float(cond_late)
    return rep


def print_spike_report(rep: dict) -> None:
    print("\n=== Analyse des pics ===")
    print(f"Barres                   : {rep['bars']}")
    print(f"Pics detectes            : {rep['spikes']} (hausse {rep['spikes_up']} / baisse {rep['spikes_down']})")
    print(f"Taille moyenne d'un pic  : {rep['avg_spike']:.4f}")
    if "avg_bars_between" in rep:
        print(f"Barres moy. entre pics   : {rep['avg_bars_between']:.1f}")
        print(f"P(pic avant m/2)         : {rep['hazard_early']:.3f}")
        print(f"P(pic dans ]m,1.5m] | >m): {rep['hazard_late']:.3f}")
        print("  -> si ces deux valeurs sont proches, les pics n'ont pas de memoire :")
        print("     attendre que le pic soit 'du' ne donne AUCUN avantage.")
    print(f"Derive moyenne par barre : {rep['drift_per_bar']:+.5f}")
    print(f"Apport des pics / barre  : {rep['spike_per_bar']:+.5f}")
    tot = rep['drift_per_bar'] * (rep['bars'] - rep['spikes']) / rep['bars'] + rep['spike_per_bar']
    print(f"=> Esperance nette/barre : {tot:+.5f}  (proche de 0 = marche equitable, pas d'avantage gratuit)")


# --------------------------------------------------------------------------
# Backtest
# --------------------------------------------------------------------------
@dataclass
class Params:
    engine: str = "drift"
    spread: float = 0.0
    spike_slippage: float = 1.0
    # drift
    lookback: int = 3000
    spike_mult: float = 6.0
    min_spikes: int = 5
    drift_ema: int = 50
    cooldown: int = 3
    sl_spike: float = 1.2
    tp_spike: float = 0.6
    max_bars: int = 120
    # trend
    fast: int = 20
    slow: int = 100
    adx_period: int = 14
    adx_min: float = 22.0
    atr_period: int = 14
    sl_atr: float = 2.0
    tp_atr: float = 4.0
    trail_atr: float = 2.5


@dataclass
class Result:
    trades_r: list = field(default_factory=list)   # resultat de chaque trade, en unites R (multiples du risque)

    def stats(self, risk_pct: float) -> dict:
        r = np.array(self.trades_r, dtype=float)
        if len(r) == 0:
            return {"trades": 0}
        wins, losses = r[r > 0], r[r <= 0]
        eq = np.cumprod(1 + r * risk_pct / 100.0)
        peak = np.maximum.accumulate(eq)
        dd = ((peak - eq) / peak).max() * 100
        se = r.std(ddof=1) / math.sqrt(len(r)) if len(r) > 1 else float("nan")
        return {
            "trades": len(r),
            "winrate": len(wins) / len(r) * 100,
            "expectancy_R": r.mean(),
            "t_stat": r.mean() / se if se and se > 0 else float("nan"),
            "profit_factor": wins.sum() / -losses.sum() if losses.sum() < 0 else float("inf"),
            "return_pct": (eq[-1] - 1) * 100,
            "max_dd_pct": dd,
        }


def _prepare(df: pd.DataFrame, p: Params) -> dict:
    o, h, l, c = (df[k].to_numpy() for k in ("open", "high", "low", "close"))
    out = {"o": o, "h": h, "l": l, "c": c}
    if "spread" in df.columns and p.spread <= 0:
        out["spr"] = df["spread"].to_numpy(dtype=float)   # converted with --point
    else:
        out["spr"] = np.full(len(df), p.spread)
    if p.engine == "drift":
        body = df["close"] - df["open"]
        absb = body.abs()
        med = absb.rolling(p.lookback, min_periods=200).median()
        thresh = med * p.spike_mult
        is_spike = absb >= thresh
        spike_body = body.where(is_spike, 0.0)
        cnt = is_spike.astype(int).rolling(p.lookback, min_periods=200).sum()
        signed = spike_body.rolling(p.lookback, min_periods=200).sum()
        absum = spike_body.abs().rolling(p.lookback, min_periods=200).sum()
        avg_spike = (absum / cnt.replace(0, np.nan)).fillna(0)
        drift_dir = np.where(cnt >= p.min_spikes, np.where(signed > 0, -1, 1), 0)
        # barres ecoulees depuis le dernier pic
        grp = is_spike.cumsum()
        since = df.groupby(grp).cumcount().to_numpy()
        since = np.where(grp.to_numpy() == 0, 10**9, since)
        e = ema(df["close"], p.drift_ema).to_numpy()
        out.update(drift_dir=drift_dir, avg_spike=avg_spike.to_numpy(),
                   since=since, ema=e, thresh=thresh.to_numpy())
    else:
        out.update(fast=ema(df["close"], p.fast).to_numpy(),
                   slow=ema(df["close"], p.slow).to_numpy(),
                   adx=adx(df, p.adx_period).to_numpy(),
                   atr=atr(df, p.atr_period).to_numpy())
    return out


def backtest(df: pd.DataFrame, p: Params) -> Result:
    d = _prepare(df, p)
    o, h, l, c, spr = d["o"], d["h"], d["l"], d["c"], d["spr"]
    n = len(c)
    res = Result()
    pos = 0
    entry = sl = tp = risk = 0.0
    opened = 0

    start = max(p.lookback if p.engine == "drift" else p.slow * 3, 2)
    i = start
    while i < n - 1:
        if pos == 0:
            sig = 0
            sl_d = tp_d = 0.0
            if p.engine == "drift":
                dd, a = d["drift_dir"][i], d["avg_spike"][i]
                if dd != 0 and a > 0 and d["since"][i] >= p.cooldown and i >= 1:
                    e0, e1 = d["ema"][i], d["ema"][i - 1]
                    ok = (c[i] > e0 and e0 > e1) if dd > 0 else (c[i] < e0 and e0 < e1)
                    if ok:
                        sig, sl_d, tp_d = dd, a * p.sl_spike, a * p.tp_spike
            else:
                f, s = d["fast"], d["slow"]
                if d["adx"][i] >= p.adx_min and d["atr"][i] > 0:
                    if f[i - 1] <= s[i - 1] and f[i] > s[i]:
                        sig = 1
                    elif f[i - 1] >= s[i - 1] and f[i] < s[i]:
                        sig = -1
                    sl_d, tp_d = d["atr"][i] * p.sl_atr, d["atr"][i] * p.tp_atr
            if sig != 0 and sl_d > 0:
                pos = sig
                entry = o[i + 1]
                sl = entry - pos * sl_d
                tp = entry + pos * tp_d if tp_d > 0 else 0.0
                risk = sl_d + spr[i + 1]
                opened = i + 1
                i += 1
            else:
                i += 1
                continue
        # --- position ouverte : traitement de la barre i ---
        exit_px = None
        if pos > 0:
            if l[i] <= sl:
                overshoot = max(sl - l[i], 0) if o[i] > sl else 0
                exit_px = (o[i] if o[i] < sl else sl - p.spike_slippage * overshoot)
            elif tp and h[i] >= tp:
                exit_px = tp
        else:
            if h[i] >= sl:
                overshoot = max(h[i] - sl, 0) if o[i] < sl else 0
                exit_px = (o[i] if o[i] > sl else sl + p.spike_slippage * overshoot)
            elif tp and l[i] <= tp:
                exit_px = tp
        if exit_px is None and p.engine == "drift" and p.max_bars > 0 and i - opened + 1 >= p.max_bars:
            exit_px = c[i]
        if exit_px is None and p.engine == "trend" and p.trail_atr > 0:
            dist = d["atr"][i] * p.trail_atr
            if pos > 0:
                sl = max(sl, c[i] - dist)
            else:
                sl = min(sl, c[i] + dist)
        if exit_px is not None:
            pnl = pos * (exit_px - entry) - spr[opened]
            res.trades_r.append(pnl / risk)
            pos = 0
        i += 1
    return res


def fmt(st: dict) -> str:
    if st.get("trades", 0) == 0:
        return "aucun trade"
    return (f"trades={st['trades']:5d}  gagnants={st['winrate']:5.1f}%  "
            f"E={st['expectancy_R']:+.3f}R  t={st['t_stat']:+.2f}  PF={st['profit_factor']:.2f}  "
            f"rendement={st['return_pct']:+8.1f}%  maxDD={st['max_dd_pct']:5.1f}%")


def optimize(df: pd.DataFrame, base: Params, risk_pct: float, split: float) -> None:
    """Recherche en grille sur l'echantillon d'apprentissage, puis verification hors echantillon."""
    cut = int(len(df) * split)
    ins, oos = df.iloc[:cut].reset_index(drop=True), df.iloc[cut:].reset_index(drop=True)
    if base.engine == "drift":
        grid = {"sl_spike": [0.8, 1.2, 2.0], "tp_spike": [0.3, 0.6, 1.0],
                "drift_ema": [20, 50, 150], "max_bars": [30, 120, 400]}
    else:
        grid = {"fast": [10, 20, 50], "slow": [100, 200], "adx_min": [0, 20, 30],
                "sl_atr": [1.5, 2.5], "tp_atr": [0, 3.0, 5.0]}
    keys = list(grid)
    rows = []
    for combo in itertools.product(*grid.values()):
        p = Params(**{**base.__dict__, **dict(zip(keys, combo))})
        if p.engine == "trend" and p.fast >= p.slow:
            continue
        st = backtest(ins, p).stats(risk_pct)
        if st.get("trades", 0) >= 30:
            rows.append((st["expectancy_R"], p, st))
    rows.sort(key=lambda x: x[0], reverse=True)
    print(f"\n=== Optimisation : {len(rows)} combinaisons testees sur {cut} barres (apprentissage) ===")
    print("Top 5 en apprentissage, et leur resultat sur les donnees JAMAIS VUES (hors echantillon) :")
    for _, p, st in rows[:5]:
        st_o = backtest(oos, p).stats(risk_pct)
        params = {k: getattr(p, k) for k in keys}
        print(f"\n  {params}")
        print(f"   IN  : {fmt(st)}")
        print(f"   OUT : {fmt(st_o)}")
    print("\nInterpretation : seul un avantage qui TIENT hors echantillon (E > 0 et t > 2)")
    print("merite un test sur compte demo. Sinon c'est de la sur-optimisation (du hasard).")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("csv", nargs="?", help="CSV de barres exporte de MT5")
    ap.add_argument("--simulate", choices=["gainx", "painx", "fxvol"], help="utiliser des donnees simulees")
    ap.add_argument("--bars", type=int, default=150_000)
    ap.add_argument("--edge", type=float, default=0.0, help="biais artificiel dans la simulation")
    ap.add_argument("--engine", choices=["drift", "trend", "auto"], default="auto")
    ap.add_argument("--spread", type=float, default=0.0, help="spread en unites de prix")
    ap.add_argument("--point", type=float, default=0.0,
                    help="taille du point : utilise la colonne SPREAD (en points) convertie en prix")
    ap.add_argument("--risk", type=float, default=0.5, help="risque par trade en %% (pour la courbe d'equity)")
    ap.add_argument("--spike-mult", type=float, default=6.0)
    ap.add_argument("--spike-slippage", type=float, default=1.0,
                    help="part du depassement d'un pic perdue au-dela du SL (1.0 = realiste, 0 = optimiste)")
    ap.add_argument("--optimize", action="store_true", help="recherche en grille + validation hors echantillon")
    ap.add_argument("--split", type=float, default=0.6, help="part d'apprentissage pour --optimize")
    args = ap.parse_args()

    if args.simulate:
        df = simulate(args.simulate, args.bars, edge=args.edge)
        name = f"simulation {args.simulate} (biais={args.edge})"
    elif args.csv:
        df = load_csv(args.csv)
        name = args.csv
    else:
        ap.error("fournir un CSV ou --simulate")

    if "spread" in df.columns:
        if args.point > 0 and args.spread <= 0:
            df["spread"] = df["spread"] * args.point
        else:
            df = df.drop(columns="spread")

    engine = args.engine
    if engine == "auto":
        low = name.lower()
        engine = "drift" if ("gainx" in low or "painx" in low) else "trend"

    print(f"Donnees : {name} — {len(df)} barres — moteur {engine.upper()}")
    rep = spike_report(df, args.spike_mult)
    print_spike_report(rep)

    p = Params(engine=engine, spread=args.spread, spike_mult=args.spike_mult,
               spike_slippage=args.spike_slippage)
    st = backtest(df, p).stats(args.risk)
    print(f"\n=== Backtest avec les parametres par defaut (risque {args.risk}%/trade) ===")
    print(fmt(st))

    if args.optimize:
        optimize(df, p, args.risk, args.split)


if __name__ == "__main__":
    main()
