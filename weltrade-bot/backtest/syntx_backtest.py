#!/usr/bin/env python3
"""
Backtester pour SyntX Guardian v2 (indices synthetiques Weltrade).

Reproduit les strategies de l'Expert Advisor MT5 sur des donnees en barres
pour verifier, AVANT de risquer de l'argent, s'il existe un vrai avantage :

  - drift     : GainX. Trade dans le sens de la derive lente, contre les pics.
  - ema_cross : croisement d'EMA + filtre ADX, sortie sur croisement inverse.
  - breakout  : cassure de canal (Donchian), sortie sur cassure inverse.
  - meanrev   : retour a la moyenne (Bollinger + RSI), seulement sans tendance.

Indices autorises : FX Vol / SFX Vol 20-40-60 et GainX. Le preset de
l'indice (identique a l'EA) est choisi d'apres le nom du fichier ou --symbol.

Donnees : CSV exporte de MT5 (script ExportBars.mq5 fourni). Colonnes :
  <DATE> <TIME> <OPEN> <HIGH> <LOW> <CLOSE> [<TICKVOL> <SPREAD>]
ou simplement : time,open,high,low,close[,spread]

Exemples :
  python syntx_backtest.py GainX_999_M1.csv --point 0.01
  python syntx_backtest.py FX_Vol_40_M15.csv --point 0.01 --compare
  python syntx_backtest.py SFX_Vol_20_H1.csv --point 0.01 --strategy breakout --optimize
  python syntx_backtest.py --simulate gainx --spread 0.3

Modele d'execution (neutre, sans biais volontaire) :
  - decision a la cloture d'une barre, execution a l'ouverture de la suivante
    (comme l'EA, qui agit a chaque nouvelle barre) ;
  - spread paye a chaque trade ;
  - ouverture au-dela du stop ou de l'objectif -> execution au prix
    d'ouverture (dans les deux sens) ;
  - stop et objectif touches dans la meme barre -> le plus proche de
    l'ouverture est suppose touche en premier ;
  - trade ignore si le spread depasse 10 % du stop (comme l'EA) ;
  - au plus 20 trades par jour (comme l'EA, --max-trades-day) ;
  - swap applique a chaque nuit passee en position (--swap-long/--swap-short) ;
  - indicateurs calcules comme MT5 (ATR = moyenne simple, ADX de Wilder) ;
  - DRIFT : quand un pic traverse le stop, le depassement est perdu
    (--spike-slippage, 1.0 = realiste) car un pic saute en un seul tick.
Limite : le plafond de risque total et la limite journaliere de l'EA
(qui portent sur tout le portefeuille) ne sont pas simules ici.
"""
from __future__ import annotations

import argparse
import itertools
import math
import os
import re
import sys
from dataclasses import dataclass, field, replace

import numpy as np
import pandas as pd

STRATEGIES = ("drift", "ema_cross", "breakout", "meanrev")
VOL_STRATEGIES = ("ema_cross", "breakout", "meanrev")

# Seuils minimaux (hors echantillon) pour considerer un indice comme rentable
CRITERIA = {
    "expectancy_R":  (0.10, "gain moyen par trade > +0,10 R"),
    # t > 2,5 et non 2 : on teste jusqu'a 27 combinaisons indice x strategie,
    # avec t > 2 environ une sur 40 "passe" par pur hasard.
    "t_stat":        (2.5,  "fiabilite statistique t > 2,5"),
    "trades":        (100,  "au moins 100 trades"),
    "profit_factor": (1.3,  "profit factor > 1,3"),
    "max_dd_pct":    (15.0, "perte max depuis un plus haut < 15 %"),
    "stable_folds":  (3,    "gagnant sur au moins 3 des 4 periodes successives"),
}
N_FOLDS = 4


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
        drift = p * spike_mean / (1 - p) * (1.0 + edge)   # equitable si edge = 0
        # GainX monte lentement et chute par pics ; PainX l'inverse.
        sign = 1.0 if kind == "gainx" else -1.0
        steps = sign * (np.where(is_spike, -spikes, drift) + noise)
    else:
        steps = rng.normal(edge * 0.01, 0.15, n)
    price = (10000.0 + np.cumsum(steps)).reshape(bars, ticks_per_bar)
    open_ = np.concatenate([[10000.0], price[:-1, -1]])
    return pd.DataFrame({
        "time": pd.date_range("2025-01-01", periods=bars, freq="min"),
        "open": open_,
        "high": np.maximum(price.max(axis=1), open_),
        "low": np.minimum(price.min(axis=1), open_),
        "close": price[:, -1],
    })


def resample(df: pd.DataFrame, rule: str) -> pd.DataFrame:
    """Regroupe des barres (ex. M1 -> M15 avec rule='15min')."""
    agg = {"open": "first", "high": "max", "low": "min", "close": "last"}
    if "spread" in df.columns:
        agg["spread"] = "mean"
    return df.set_index("time").resample(rule).agg(agg).dropna().reset_index()


# --------------------------------------------------------------------------
# Indicateurs (memes definitions que MT5)
# --------------------------------------------------------------------------
def ema(s: pd.Series, n: int) -> pd.Series:
    return s.ewm(span=n, adjust=False).mean()


def true_range(df: pd.DataFrame) -> pd.Series:
    pc = df["close"].shift()
    return pd.concat([df["high"] - df["low"], (df["high"] - pc).abs(), (df["low"] - pc).abs()],
                     axis=1).max(axis=1)


def atr(df: pd.DataFrame, n: int) -> pd.Series:
    """Comme iATR de MT5 : moyenne SIMPLE du true range."""
    return true_range(df).rolling(n, min_periods=1).mean()


def adx(df: pd.DataFrame, n: int) -> pd.Series:
    """Comme iADXWilder de MT5 (lissage de Wilder). L'EA utilise iADXWilder."""
    up = df["high"].diff()
    dn = -df["low"].diff()
    plus_dm = np.where((up > dn) & (up > 0), up, 0.0)
    minus_dm = np.where((dn > up) & (dn > 0), dn, 0.0)
    a = true_range(df).ewm(alpha=1 / n, adjust=False).mean()
    pdi = 100 * pd.Series(plus_dm, index=df.index).ewm(alpha=1 / n, adjust=False).mean() / a
    mdi = 100 * pd.Series(minus_dm, index=df.index).ewm(alpha=1 / n, adjust=False).mean() / a
    dx = 100 * (pdi - mdi).abs() / (pdi + mdi).replace(0, np.nan)
    return dx.ewm(alpha=1 / n, adjust=False).mean().fillna(0)


def rsi(s: pd.Series, n: int) -> pd.Series:
    d = s.diff()
    gain = d.clip(lower=0).ewm(alpha=1 / n, adjust=False).mean()
    loss = (-d.clip(upper=0)).ewm(alpha=1 / n, adjust=False).mean()
    return (100 - 100 / (1 + gain / loss.replace(0, np.nan))).fillna(50)


def bollinger(s: pd.Series, n: int, dev: float):
    mid = s.rolling(n).mean()
    sd = s.rolling(n).std(ddof=0)   # MT5 utilise l'ecart-type de population
    return mid, mid + dev * sd, mid - dev * sd


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
        "spikes": int(len(idx)),
        "spikes_up": int((body[is_spike] > 0).sum()),
        "spikes_down": int((body[is_spike] < 0).sum()),
        "avg_spike": float(body[is_spike].abs().mean()) if len(idx) else 0.0,
        "drift_per_bar": float(body[~is_spike].mean()),
        "spike_per_bar": float(body[is_spike].sum() / len(df)),
    }
    if len(idx) > 20:
        gaps = np.diff(idx)
        m = np.median(gaps)
        rep["avg_bars_between"] = float(gaps.mean())
        # Absence de memoire : P(pic tot) doit egaler P(pic tot | deja attendu m barres)
        rep["hazard_early"] = float((gaps <= m / 2).sum() / len(gaps))
        rep["hazard_late"] = float(((gaps > m) & (gaps <= 1.5 * m)).sum() / max((gaps > m).sum(), 1))
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
    tot = rep["drift_per_bar"] * (rep["bars"] - rep["spikes"]) / rep["bars"] + rep["spike_per_bar"]
    print(f"=> Esperance nette/barre : {tot:+.5f}  (proche de 0 = marche equitable, pas d'avantage gratuit)")


# --------------------------------------------------------------------------
# Parametres et presets (identiques a SyntX_Guardian.mq5)
# --------------------------------------------------------------------------
@dataclass
class Params:
    strategy: str = "ema_cross"
    spread: float = 0.0
    spike_slippage: float = 1.0
    max_spread_sl_ratio: float = 0.10  # comme l'EA : trade ignore si spread > 10 % du stop
    swap_long: float = 0.0             # swap par nuit en unites de prix (+ = credit)
    max_trades_per_day: int = 20       # comme l'EA (InpMaxTradesPerDay), 0 = illimite
    swap_short: float = 0.0
    expected_drift: int = 0          # +1 pour GainX (securite)
    max_bars: int = 0                # sortie temporelle (drift, meanrev)
    # drift
    lookback: int = 3000
    spike_mult: float = 6.0
    min_spikes: int = 5
    drift_ema: int = 50
    cooldown: int = 3
    sl_spike: float = 1.2
    tp_spike: float = 0.6
    # ema_cross / breakout
    fast: int = 20
    slow: int = 100
    adx_period: int = 14
    adx_min: float = 22.0
    atr_period: int = 14
    sl_atr: float = 2.0
    tp_atr: float = 4.0
    trail_atr: float = 2.5
    brk_period: int = 20
    # meanrev
    bb_period: int = 20
    bb_dev: float = 2.0
    rsi_period: int = 14
    rsi_low: float = 30.0
    adx_max_mr: float = 25.0
    mr_sl_atr: float = 2.0


def _vol(tf, risk, fast, slow, adx_min, sl, tp, trail, brk, bb_dev, rsi_low, adx_max, mr_sl):
    return dict(tf=tf, risk_mult=risk, strategy="ema_cross", fast=fast, slow=slow, adx_min=adx_min,
                sl_atr=sl, tp_atr=tp, trail_atr=trail, brk_period=brk, bb_dev=bb_dev,
                rsi_low=rsi_low, adx_max_mr=adx_max, mr_sl_atr=mr_sl)


PRESETS: dict[tuple[str, int], dict] = {
    #                     UT    risque fast slow ADX  SL   TP   trail canal BBdev RSIbas ADXmaxMR SL_MR
    ("FXVOL", 20):  _vol("H1",  1.0, 20, 100, 20, 2.0, 4.0, 2.5, 20, 2.0, 30, 25, 2.0),
    ("FXVOL", 40):  _vol("M15", 1.0, 20, 100, 22, 2.2, 4.0, 2.5, 30, 2.0, 30, 25, 2.2),
    ("FXVOL", 60):  _vol("M15", 0.8, 30, 150, 25, 2.5, 4.5, 3.0, 40, 2.2, 28, 25, 2.5),
    ("SFXVOL", 20): _vol("H1",  1.0, 20, 120, 22, 2.2, 4.0, 2.8, 25, 2.0, 30, 25, 2.2),
    ("SFXVOL", 40): _vol("M15", 0.8, 25, 150, 25, 2.5, 4.5, 3.0, 35, 2.2, 28, 25, 2.5),
    ("SFXVOL", 60): _vol("M15", 0.6, 30, 200, 28, 3.0, 5.0, 3.5, 45, 2.2, 28, 25, 3.0),
}
_GAINX = {  # niveau: (risque, lookback, EMA, attente, SL pic, TP pic, barres max)
    400:  (0.7, 2000, 30, 2, 1.3, 0.5, 30),
    600:  (0.8, 2500, 40, 3, 1.2, 0.6, 45),
    800:  (0.9, 3000, 50, 3, 1.2, 0.6, 60),
    999:  (1.0, 3500, 50, 4, 1.2, 0.6, 80),
    1200: (1.0, 4000, 60, 4, 1.1, 0.7, 100),
}
for _lvl, (_r, _lb, _e, _cd, _sl, _tp, _mb) in _GAINX.items():
    PRESETS[("GAINX", _lvl)] = dict(tf="M1", risk_mult=_r, strategy="drift", lookback=_lb, drift_ema=_e,
                                    cooldown=_cd, sl_spike=_sl, tp_spike=_tp, max_bars=_mb,
                                    expected_drift=1)


def detect_index(name: str) -> tuple[str | None, int | None]:
    """Identifie l'indice a partir d'un nom de symbole ou de fichier."""
    s = re.sub(r"[\s._\-]", "", os.path.basename(name).upper())
    for fam in ("SFXVOL", "FXVOL", "GAINX"):   # SFX avant FX (SFXVOL contient FXVOL)
        m = re.search(fam + r"(\d+)?", s)
        if m:
            return fam, int(m.group(1)) if m.group(1) else None
    return None, None


def find_preset(fam: str | None, level: int | None) -> tuple[str, dict] | None:
    if fam == "GAINX":
        lvl = min(_GAINX, key=lambda k: abs(k - (level or 999)))
        return f"GainX {lvl}", PRESETS[("GAINX", lvl)]
    if (fam, level) in PRESETS:
        label = {"FXVOL": "FX Vol", "SFXVOL": "SFX Vol"}[fam]
        return f"{label} {level}", PRESETS[(fam, level)]
    return None


def detect_tf(name: str) -> str | None:
    m = re.search(r"(?:^|[_\-. ])(M1|M5|M15|M30|H1|H4)(?:[_\-. ]|$)", os.path.basename(name).upper())
    return m.group(1) if m else None


# Fichier de calibration partage avec l'EA (Common\\Files\\SyntX_Guardian_presets.csv) :
# une ligne par reglage : indice,cle,valeur  (ex. "FX Vol 40,sl_atr,2.5")
OVERRIDE_KEYS = ("enabled", "tf", "strategy", "risk_mult", "fast", "slow", "adx_min", "sl_atr", "tp_atr",
                 "trail_atr", "brk_period", "bb_dev", "rsi_low", "adx_max_mr", "mr_sl_atr", "max_bars",
                 "lookback", "drift_ema", "cooldown", "sl_spike", "tp_spike", "spike_mult", "min_spikes")
PRESET_FILE = "SyntX_Guardian_presets.csv"


def load_overrides(path: str) -> dict[str, dict[str, str]]:
    out: dict[str, dict[str, str]] = {}
    with open(path, encoding="utf-8-sig") as fh:
        for line in fh:
            parts = [x.strip() for x in line.split(",")]
            if len(parts) != 3 or parts[0].startswith("#") or parts[0].lower() == "index":
                continue
            name, key, val = parts
            if key not in OVERRIDE_KEYS:
                raise ValueError(f"cle inconnue dans {path} : {key}")
            out.setdefault(name.lower(), {})[key] = val
    return out


def apply_overrides(preset: dict, overrides: dict[str, str]) -> dict:
    """Applique les valeurs calibrees sur un preset (types convertis)."""
    d = dict(preset)
    types = {f: type(v) for f, v in Params().__dict__.items()}
    for k, v in overrides.items():
        if k == "enabled":
            continue
        if k in ("tf", "strategy"):
            d[k] = v
        elif k == "risk_mult":
            d[k] = float(v)
        else:
            d[k] = types[k](float(v)) if types[k] is int else types[k](v)
    return d


def write_overrides(path: str, rows: list[tuple[str, str, object]]) -> None:
    # Fins de ligne Windows (CRLF) : format attendu par la lecture CSV de MT5
    with open(path, "w", encoding="ascii", newline="\r\n") as fh:
        fh.write("index,key,value\n")
        for name, key, val in rows:
            if key not in OVERRIDE_KEYS:
                raise ValueError(key)
            fh.write(f"{name},{key},{val}\n")


def apply_preset(preset: dict | None, strategy: str | None, base: Params) -> tuple[Params, float, str | None]:
    """Retourne (parametres, multiplicateur de risque, UT conseillee)."""
    tf, risk_mult, p = None, 1.0, base
    if preset:
        d = dict(preset)
        tf = d.pop("tf")
        risk_mult = d.pop("risk_mult")
        p = replace(base, **d)
    if strategy:
        p = replace(p, strategy=strategy)
    # sortie temporelle : seulement drift (preset) et retour a la moyenne
    if p.strategy == "meanrev":
        p = replace(p, max_bars=p.max_bars or 40)
    elif p.strategy in ("ema_cross", "breakout"):
        p = replace(p, max_bars=0)
    elif p.strategy == "drift" and not p.max_bars:
        p = replace(p, max_bars=120)
    return p, risk_mult, tf


# --------------------------------------------------------------------------
# Backtest
# --------------------------------------------------------------------------
@dataclass
class Result:
    trades_r: list = field(default_factory=list)   # resultat de chaque trade, en R
    trades: list = field(default_factory=list)     # (barre d'entree, barre de sortie, sens, R)

    def stats(self, risk_pct: float) -> dict:
        return stats_from_r(np.array(self.trades_r, dtype=float), risk_pct)


def stats_from_r(r: np.ndarray, risk_pct: float) -> dict:
    if len(r) == 0:
        return {"trades": 0}
    wins, losses = r[r > 0], r[r <= 0]
    eq = np.cumprod(1 + r * risk_pct / 100.0)
    peak = np.maximum.accumulate(np.concatenate([[1.0], eq]))[1:]
    dd = ((peak - eq) / peak).max() * 100
    se = r.std(ddof=1) / math.sqrt(len(r)) if len(r) > 1 else float("nan")
    return {
        "trades": len(r),
        "winrate": len(wins) / len(r) * 100,
        "expectancy_R": float(r.mean()),
        "t_stat": float(r.mean() / se) if se and se > 0 else float("nan"),
        "profit_factor": float(wins.sum() / -losses.sum()) if losses.sum() < 0 else float("inf"),
        "return_pct": float((eq[-1] - 1) * 100),
        "max_dd_pct": float(dd),
    }


def _prepare(df: pd.DataFrame, p: Params) -> dict:
    out = {k: df[k].to_numpy(dtype=float) for k in ("open", "high", "low", "close")}
    if pd.api.types.is_datetime64_any_dtype(df["time"]):
        out["day"] = (df["time"].dt.normalize() - pd.Timestamp("1970-01-01")).dt.days.to_numpy()
    else:
        out["day"] = np.zeros(len(df), dtype=int)
    if "spread" in df.columns:
        out["spr"] = df["spread"].to_numpy(dtype=float)
    else:
        out["spr"] = np.full(len(df), p.spread)
    close = df["close"]

    if p.strategy == "drift":
        body = close - df["open"]
        absb = body.abs()
        mp = min(200, p.lookback)
        med = absb.rolling(p.lookback, min_periods=mp).median()
        is_spike = absb >= med * p.spike_mult
        spike_body = body.where(is_spike, 0.0)
        cnt = is_spike.astype(int).rolling(p.lookback, min_periods=mp).sum()
        signed = spike_body.rolling(p.lookback, min_periods=mp).sum()
        absum = spike_body.abs().rolling(p.lookback, min_periods=mp).sum()
        avg_spike = (absum / cnt.replace(0, np.nan)).fillna(0)
        drift_dir = np.where(cnt >= p.min_spikes, np.where(signed > 0, -1, 1), 0)
        if p.expected_drift:
            drift_dir = np.where(drift_dir == p.expected_drift, drift_dir, 0)
        grp = is_spike.cumsum()
        since = df.groupby(grp).cumcount().to_numpy()
        since = np.where(grp.to_numpy() == 0, 10**9, since)
        out.update(drift_dir=drift_dir, avg_spike=avg_spike.to_numpy(), since=since,
                   ema=ema(close, p.drift_ema).to_numpy())
        return out

    out["atr"] = atr(df, p.atr_period).to_numpy()
    out["adx"] = adx(df, p.adx_period).to_numpy()
    if p.strategy == "ema_cross":
        out["fast"] = ema(close, p.fast).to_numpy()
        out["slow"] = ema(close, p.slow).to_numpy()
    elif p.strategy == "breakout":
        n, nx = p.brk_period, max(p.brk_period // 2, 2)
        # canal des n barres PRECEDENTES (la barre qui casse est exclue)
        out["ch_hi"] = df["high"].rolling(n).max().shift(1).to_numpy()
        out["ch_lo"] = df["low"].rolling(n).min().shift(1).to_numpy()
        out["ex_hi"] = df["high"].rolling(nx).max().shift(1).to_numpy()
        out["ex_lo"] = df["low"].rolling(nx).min().shift(1).to_numpy()
    elif p.strategy == "meanrev":
        mid, up, lo = bollinger(close, p.bb_period, p.bb_dev)
        out.update(mid=mid.to_numpy(), up=up.to_numpy(), lo=lo.to_numpy(),
                   rsi=rsi(close, p.rsi_period).to_numpy())
    return out


def _entry(d: dict, p: Params, i: int) -> tuple[int, float, float]:
    """Signal a la cloture de la barre i -> (sens, distance stop, distance objectif)."""
    c = d["close"]
    if p.strategy == "drift":
        dd, a = d["drift_dir"][i], d["avg_spike"][i]
        if dd == 0 or a <= 0 or d["since"][i] < p.cooldown:
            return 0, 0.0, 0.0
        e0, e1 = d["ema"][i], d["ema"][i - 1]
        ok = (c[i] > e0 and e0 > e1) if dd > 0 else (c[i] < e0 and e0 < e1)
        return (int(dd), a * p.sl_spike, a * p.tp_spike) if ok else (0, 0.0, 0.0)

    a = d["atr"][i]
    if not a > 0:
        return 0, 0.0, 0.0
    if p.strategy == "ema_cross":
        f, s = d["fast"], d["slow"]
        if d["adx"][i] < p.adx_min:
            return 0, 0.0, 0.0
        if f[i - 1] <= s[i - 1] and f[i] > s[i]:
            return 1, a * p.sl_atr, a * p.tp_atr
        if f[i - 1] >= s[i - 1] and f[i] < s[i]:
            return -1, a * p.sl_atr, a * p.tp_atr
    elif p.strategy == "breakout":
        hi, lo = d["ch_hi"], d["ch_lo"]
        if c[i] > hi[i] and c[i - 1] <= hi[i - 1]:
            return 1, a * p.sl_atr, a * p.tp_atr
        if c[i] < lo[i] and c[i - 1] >= lo[i - 1]:
            return -1, a * p.sl_atr, a * p.tp_atr
    elif p.strategy == "meanrev":
        if d["adx"][i] > p.adx_max_mr:
            return 0, 0.0, 0.0
        if c[i] < d["lo"][i] and d["rsi"][i] < p.rsi_low:
            return 1, a * p.mr_sl_atr, 0.0
        if c[i] > d["up"][i] and d["rsi"][i] > 100 - p.rsi_low:
            return -1, a * p.mr_sl_atr, 0.0
    return 0, 0.0, 0.0


def _signal_exit(d: dict, p: Params, i: int, pos: int) -> bool:
    c = d["close"][i]
    if p.strategy == "ema_cross":
        return d["fast"][i] < d["slow"][i] if pos > 0 else d["fast"][i] > d["slow"][i]
    if p.strategy == "breakout":
        return c < d["ex_lo"][i] if pos > 0 else c > d["ex_hi"][i]
    if p.strategy == "meanrev":
        return c >= d["mid"][i] if pos > 0 else c <= d["mid"][i]
    return False


def backtest(df: pd.DataFrame, p: Params) -> Result:
    d = _prepare(df, p)
    o, h, l, c, spr = d["open"], d["high"], d["low"], d["close"], d["spr"]
    n = len(c)
    res = Result()

    start = {"drift": p.lookback, "ema_cross": p.slow * 3,
             "breakout": p.brk_period + 50, "meanrev": max(p.bb_period, 50) + 50}[p.strategy]
    start = max(start, 2)

    day = d["day"]
    trades_today, today = 0, None
    pos = 0
    entry = sl = tp = sl_d = cost = 0.0
    opened = 0

    def close_at(px: float, j: int) -> None:
        nonlocal pos
        swap = p.swap_long if pos > 0 else p.swap_short
        pnl = pos * (px - entry) - cost + swap * (day[j] - day[opened])
        r = pnl / sl_d
        res.trades_r.append(r)
        res.trades.append((opened, j, pos, r))
        pos = 0

    for i in range(start, n - 1):
        # --- decision a la cloture de la barre i, execution a l'ouverture de i+1 ---
        if pos != 0:
            time_up = p.max_bars > 0 and (i + 1 - opened) >= p.max_bars
            if time_up or _signal_exit(d, p, i, pos):
                close_at(o[i + 1], i + 1)
        if pos == 0:
            sig, sdist, tdist = _entry(d, p, i)
            if sig != 0 and p.max_spread_sl_ratio > 0 and spr[i + 1] > p.max_spread_sl_ratio * sdist:
                sig = 0   # spread trop eleve par rapport au stop (meme filtre que l'EA)
            if sig != 0 and p.max_trades_per_day > 0:
                if day[i + 1] != today:
                    today, trades_today = day[i + 1], 0
                if trades_today >= p.max_trades_per_day:
                    sig = 0   # plafond journalier de l'EA atteint
            if sig != 0 and sdist > 0:
                trades_today += 1
                pos, sl_d, opened = sig, sdist, i + 1
                entry, cost = o[i + 1], spr[i + 1]
                sl = entry - pos * sdist
                tp = entry + pos * tdist if tdist > 0 else 0.0
        elif p.trail_atr > 0 and p.strategy in ("ema_cross", "breakout"):
            dist = d["atr"][i] * p.trail_atr
            sl = max(sl, c[i] - dist) if pos > 0 else min(sl, c[i] + dist)

        # --- deroulement de la barre i+1 : stop / objectif ---
        if pos == 0:
            continue
        j = i + 1
        slip = p.spike_slippage if p.strategy == "drift" else 0.0
        exit_px = None
        if pos > 0:
            if o[j] <= sl or (tp and o[j] >= tp):
                exit_px = o[j]                      # ouverture au-dela : prix d'ouverture
            else:
                hit_sl, hit_tp = l[j] <= sl, bool(tp) and h[j] >= tp
                if hit_sl and hit_tp:               # le plus proche de l'ouverture d'abord
                    hit_sl = (o[j] - sl) <= (tp - o[j])
                    hit_tp = not hit_sl
                if hit_sl:
                    exit_px = sl - slip * (sl - l[j])
                elif hit_tp:
                    exit_px = tp
        else:
            if o[j] >= sl or (tp and o[j] <= tp):
                exit_px = o[j]
            else:
                hit_sl, hit_tp = h[j] >= sl, bool(tp) and l[j] <= tp
                if hit_sl and hit_tp:
                    hit_sl = (sl - o[j]) <= (o[j] - tp)
                    hit_tp = not hit_sl
                if hit_sl:
                    exit_px = sl + slip * (h[j] - sl)
                elif hit_tp:
                    exit_px = tp
        if exit_px is not None:
            close_at(exit_px, j)
    return res


# --------------------------------------------------------------------------
# Affichage, verdict, optimisation
# --------------------------------------------------------------------------
def evaluate(df: pd.DataFrame, p: Params, risk_pct: float) -> dict:
    """Statistiques + stabilite : nombre de periodes successives gagnantes."""
    st = backtest(df, p).stats(risk_pct)
    n = len(df)
    folds = 0
    for f in range(N_FOLDS):
        part = df.iloc[f * n // N_FOLDS:(f + 1) * n // N_FOLDS].reset_index(drop=True)
        sf = backtest(part, p).stats(risk_pct)
        folds += int(sf.get("trades", 0) > 0 and sf["expectancy_R"] > 0)
    st["stable_folds"] = folds
    return st


def fmt(st: dict) -> str:
    if st.get("trades", 0) == 0:
        return "aucun trade"
    return (f"trades={st['trades']:5d}  gagnants={st['winrate']:5.1f}%  "
            f"E={st['expectancy_R']:+.3f}R  t={st['t_stat']:+.2f}  PF={st['profit_factor']:.2f}  "
            f"rendement={st['return_pct']:+8.1f}%  maxDD={st['max_dd_pct']:5.1f}%")


def verdict(st: dict) -> tuple[bool, list[str]]:
    """Verifie les seuils minimaux. Retourne (valide, lignes de detail)."""
    lines, ok_all = [], True
    has = st.get("trades", 0) > 0
    for key, (thr, label) in CRITERIA.items():
        val = st.get(key, 0) if has else 0
        if key == "max_dd_pct":
            ok = val < thr
        elif key in ("trades", "stable_folds"):
            ok = val >= thr
        else:
            ok = val > thr
        ok = ok and has
        ok_all &= ok
        shown = f"{val:.2f}" if isinstance(val, float) else str(val)
        if key == "stable_folds":
            shown += f"/{N_FOLDS}"
        lines.append(f"  [{'OK ' if ok else 'NON'}] {label} (obtenu : {shown})")
    return ok_all, lines


GRIDS = {
    "drift": {"sl_spike": [0.8, 1.2, 2.0], "tp_spike": [0.3, 0.6, 1.0],
              "drift_ema": [20, 50, 150], "max_bars": [30, 120, 400]},
    "ema_cross": {"fast": [10, 20, 50], "slow": [100, 200], "adx_min": [0, 20, 30],
                  "sl_atr": [1.5, 2.5], "tp_atr": [0, 3.0, 5.0]},
    "breakout": {"brk_period": [10, 20, 40, 60], "sl_atr": [1.5, 2.5, 3.5],
                 "tp_atr": [0, 3.0, 6.0], "trail_atr": [0, 2.5, 4.0]},
    "meanrev": {"bb_dev": [1.8, 2.2, 2.6], "rsi_low": [25, 30, 35], "adx_max_mr": [20, 25, 30, 100],
                "mr_sl_atr": [1.5, 2.5, 3.5], "max_bars": [20, 60]},
}


def select_best(train: pd.DataFrame, base: Params, risk_pct: float,
                min_trades: int = 50) -> tuple[Params | None, dict, list]:
    """Recherche en grille sur l'apprentissage. Le critere de choix est la
    fiabilite t (gain moyen ET nombre de trades), pas le gain moyen seul,
    pour ne pas favoriser les reglages a 30 trades chanceux."""
    grid = GRIDS[base.strategy]
    keys = list(grid)
    rows = []
    for combo in itertools.product(*grid.values()):
        p = replace(base, **dict(zip(keys, combo)))
        if p.strategy == "ema_cross" and p.fast >= p.slow:
            continue
        st = backtest(train, p).stats(risk_pct)
        if st.get("trades", 0) >= min_trades and not math.isnan(st["t_stat"]):
            rows.append((st["t_stat"], p, st))
    rows.sort(key=lambda x: x[0], reverse=True)
    if not rows:
        return None, {}, keys
    return rows[0][1], rows[0][2], keys


def optimize(df: pd.DataFrame, base: Params, risk_pct: float, split: float) -> tuple[bool, Params | None, dict]:
    """Apprentissage sur le debut de l'historique, puis UN SEUL test (le meilleur
    reglage) sur la fin, jamais vue. Tester plusieurs reglages sur la fin
    reviendrait a la "consommer" et a laisser passer des faux positifs."""
    cut = int(len(df) * split)
    train, test = df.iloc[:cut].reset_index(drop=True), df.iloc[cut:].reset_index(drop=True)
    best, st_in, keys = select_best(train, base, risk_pct)
    print(f"\n=== Optimisation {base.strategy} : apprentissage {cut} barres, test final {len(test)} barres ===")
    if best is None:
        print("Aucun reglage avec assez de trades en apprentissage.")
        return False, None, {}
    st_out = evaluate(test, best, risk_pct)
    ok, lines = verdict(st_out)
    print(f"  Meilleur reglage : {({k: getattr(best, k) for k in keys})}")
    print(f"   apprentissage : {fmt(st_in)}")
    print(f"   test final    : {fmt(st_out)}")
    print(f"   => {'VALIDE' if ok else 'NON VALIDE'} sur la periode jamais vue")
    for line in lines:
        print("   " + line)
    return ok, best, st_out


def run_one(df: pd.DataFrame, p: Params, risk: float, label: str) -> dict:
    st = evaluate(df, p, risk)
    print(f"\n=== {label} | strategie {p.strategy} | risque {risk:.2f}%/trade ===")
    print(fmt(st))
    ok, lines = verdict(st)
    print(f"=> {'PROMETTEUR' if ok else 'NON VALIDE'} sur tout l'historique "
          f"(a confirmer avec --optimize, puis en demo)")
    for line in lines:
        print(line)
    return st


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("csv", nargs="?", help="CSV de barres exporte de MT5")
    ap.add_argument("--symbol", help="nom de l'indice (sinon deduit du nom du fichier), ex. 'FX Vol 40'")
    ap.add_argument("--strategy", choices=STRATEGIES, help="strategie (sinon celle du preset)")
    ap.add_argument("--compare", action="store_true", help="comparer les 3 strategies FX/SFX Vol")
    ap.add_argument("--resample", help="regrouper les barres avant le test (ex. 15min, 1h)")
    ap.add_argument("--simulate", choices=["gainx", "painx", "fxvol"], help="utiliser des donnees simulees")
    ap.add_argument("--bars", type=int, default=150_000)
    ap.add_argument("--edge", type=float, default=0.0, help="biais artificiel dans la simulation")
    ap.add_argument("--no-preset", action="store_true", help="ignorer le preset de l'indice")
    ap.add_argument("--force", action="store_true", help="autoriser un indice hors liste (deconseille)")
    ap.add_argument("--spread", type=float, default=0.0, help="spread en unites de prix")
    ap.add_argument("--point", type=float, default=0.0,
                    help="taille du point : utilise la colonne SPREAD (en points) convertie en prix")
    ap.add_argument("--risk", type=float, default=0.5, help="risque de base par trade en %% (module par le preset)")
    ap.add_argument("--spike-slippage", type=float, default=1.0,
                    help="DRIFT : part du depassement d'un pic perdue au-dela du SL (1.0 = realiste)")
    ap.add_argument("--optimize", action="store_true", help="recherche en grille + validation hors echantillon")
    ap.add_argument("--split", type=float, default=0.7, help="part d'apprentissage pour --optimize")
    ap.add_argument("--max-spread-ratio", type=float, default=0.10,
                    help="trade ignore si spread > X fois la distance du stop (comme l'EA)")
    ap.add_argument("--max-trades-day", type=int, default=20, help="plafond journalier (comme l'EA)")
    ap.add_argument("--swap-long", type=float, default=0.0, help="swap par nuit, achat (unites de prix, + = credit)")
    ap.add_argument("--swap-short", type=float, default=0.0, help="swap par nuit, vente (unites de prix)")
    ap.add_argument("--presets", help="fichier de calibration SyntX_Guardian_presets.csv a appliquer")
    args = ap.parse_args()

    if args.simulate:
        df = simulate(args.simulate, args.bars, edge=args.edge)
        name = f"simulation {args.simulate} (biais={args.edge})"
        sym = args.symbol or {"gainx": "GainX 999", "fxvol": "FX Vol 40", "painx": "PainX"}[args.simulate]
    elif args.csv:
        df = load_csv(args.csv)
        name = args.csv
        sym = args.symbol or args.csv
    else:
        ap.error("fournir un CSV ou --simulate")

    fam, level = detect_index(sym)
    found = find_preset(fam, level)
    preset = found[1] if (found and not args.no_preset) else None
    if found is None and not (args.force or args.simulate):
        sys.exit(f"'{sym}' n'est pas dans la liste autorisee (FX Vol / SFX Vol 20-40-60, GainX). "
                 "Utilisez --symbol si le nom du fichier ne contient pas l'indice, ou --force.")

    if "spread" in df.columns:
        if args.point > 0 and args.spread <= 0:
            df["spread"] = df["spread"] * args.point
        else:
            df = df.drop(columns="spread")
    if args.resample:
        df = resample(df, args.resample)

    default_strat = None if preset else ("drift" if fam == "GAINX" or "painx" in sym.lower() else "ema_cross")
    base = Params(spread=args.spread, spike_slippage=args.spike_slippage,
                  max_spread_sl_ratio=args.max_spread_ratio,
                  swap_long=args.swap_long, swap_short=args.swap_short,
                  max_trades_per_day=args.max_trades_day)
    if args.presets and found:
        overrides = load_overrides(args.presets).get(found[0].lower())
        if overrides:
            preset = None if args.no_preset else apply_overrides(found[1], overrides)
            if overrides.get("enabled") == "0":
                print(f"NOTE : {found[0]} est DESACTIVE dans la calibration.")
    p0, risk_mult, tf = apply_preset(preset, args.strategy or default_strat, base)
    risk = args.risk * risk_mult
    label = f"preset {found[0]} (UT conseillee {tf})" if preset else "parametres par defaut"

    if p0.strategy == "drift" and fam not in (None, "GAINX") and not args.force:
        sys.exit("La strategie drift est reservee a GainX.")
    if p0.strategy != "drift" and fam == "GAINX" and not args.force:
        sys.exit("GainX utilise uniquement la strategie drift.")

    if preset:
        data_tf = None if args.resample else detect_tf(name)
        if data_tf and data_tf != tf:
            print(f"ATTENTION : donnees en {data_tf} mais le preset est prevu pour {tf}. "
                  f"Exportez les barres {tf} (ou changez l'UT de l'indice dans l'EA).")

    print(f"Donnees : {name} — {len(df)} barres — {label}")
    if p0.strategy == "drift":
        print_spike_report(spike_report(df, p0.spike_mult))

    strategies = VOL_STRATEGIES if (args.compare and p0.strategy != "drift") else (p0.strategy,)
    for strat in strategies:
        p = p0 if strat == p0.strategy else apply_preset(preset, strat, base)[0]
        run_one(df, p, risk, label)
        if args.optimize:
            optimize(df, p, risk, args.split)


if __name__ == "__main__":
    main()
