#!/usr/bin/env python3
"""
Calibration de SyntX Guardian a partir des vraies donnees Weltrade.

Prend le dossier produit par le script MT5 ExportBars (un CSV par indice et
par unite de temps, plus SyntX_specs.csv avec les caracteristiques reelles de
chaque symbole) et, pour CHAQUE indice :

  1. coupe l'historique en deux : apprentissage (debut) et test final (fin) ;
  2. sur l'apprentissage seulement, essaie toutes les combinaisons
     unite de temps x strategie x reglages et garde la plus fiable ;
  3. evalue CE SEUL reglage sur le test final, jamais vu ;
  4. active l'indice s'il passe tous les seuils, le DESACTIVE sinon.

Un indice sans donnees est desactive (il n'a pas ete valide).

Sortie : SyntX_Guardian_presets.csv, a copier dans le dossier commun de MT5
(Common\\Files). L'EA le lit au demarrage (InpUseCalibration = true).

Exemple :
  python calibrate.py "C:/.../Common/Files/SyntX_data" --out SyntX_Guardian_presets.csv
"""
from __future__ import annotations

import argparse
import glob
import math
import os
import sys
from dataclasses import replace

import pandas as pd

import syntx_backtest as sb

ALLOWED = [("FX Vol", "FXVOL", lv) for lv in (20, 40, 60)] + \
          [("SFX Vol", "SFXVOL", lv) for lv in (20, 40, 60)] + \
          [("GainX", "GAINX", lv) for lv in (400, 600, 800, 999, 1200)]

# Durees minimales d'historique conseillees par UT (en jours)
MIN_DAYS = {"M1": 180, "M5": 270, "M15": 365, "M30": 540, "H1": 730, "H4": 1095}


def load_specs(folder: str) -> dict[str, dict]:
    path = os.path.join(folder, "SyntX_specs.csv")
    if not os.path.exists(path):
        return {}
    df = pd.read_csv(path)
    out = {}
    for _, row in df.iterrows():
        fam, lvl = sb.detect_index(str(row["symbol"]))
        if fam:
            out[f"{fam}{lvl}"] = row.to_dict()
    return out


def swap_in_price(spec: dict, side: str, ref_price: float) -> float:
    """Convertit le swap MT5 en unites de prix par nuit pour 1 lot (+ = credit)."""
    mode = int(spec.get("swap_mode", 0))
    val = float(spec.get(f"swap_{side}", 0.0))
    point = float(spec.get("point", 0.0))
    tick_size = float(spec.get("tick_size", 0.0))
    tick_value = float(spec.get("tick_value", 0.0))
    if mode == 0 or val == 0:
        return 0.0
    if mode == 1:                       # en points
        return val * point
    if mode in (2, 3, 4):               # en argent par lot
        return val * tick_size / tick_value if tick_value > 0 else 0.0
    if mode in (5, 6):                  # interet annuel en %
        return ref_price * val / 100.0 / 360.0
    print(f"  ! mode de swap {mode} non gere : swap ignore")
    return 0.0


def prepare_df(path: str, spec: dict, spread_override: float) -> tuple[pd.DataFrame, float]:
    df = sb.load_csv(path)
    point = float(spec.get("point", 0.0)) if spec else 0.0
    if spread_override > 0:
        df = df.drop(columns="spread", errors="ignore")
        return df, spread_override
    if "spread" in df.columns and point > 0:
        df["spread"] = df["spread"].astype(float) * point
        return df, 0.0
    df = df.drop(columns="spread", errors="ignore")
    if spec and point > 0:
        return df, float(spec.get("spread_points", 0)) * point
    print(f"  ! spread inconnu pour {os.path.basename(path)} : exportez avec ExportBars ou passez --spread")
    return df, 0.0


def calibrate_index(label: str, fam: str, level: int, files: list[str], spec: dict,
                    args) -> tuple[bool, dict | None, list[str]]:
    found = sb.find_preset(fam, level)
    preset = found[1]
    strategies = ("drift",) if fam == "GAINX" else sb.VOL_STRATEGIES
    log = []
    best = None   # (t_in, p, tf, df, risk, st_in)

    for path in files:
        tf = sb.detect_tf(path)
        df, spread = prepare_df(path, spec, args.spread)
        if fam == "GAINX" and tf not in ("M1", "M5"):
            log.append(f"  {os.path.basename(path)} ignore : GainX se trade en M1/M5")
            continue
        days = (df["time"].iloc[-1] - df["time"].iloc[0]).days if len(df) > 1 else 0
        if days < MIN_DAYS.get(tf or "", 365):
            log.append(f"  ! {os.path.basename(path)} : {days} jours d'historique "
                       f"(conseille >= {MIN_DAYS.get(tf or '', 365)}) -> resultats peu fiables")
        ref_price = float(df["close"].median())
        base = sb.Params(spread=spread, spike_slippage=args.spike_slippage,
                         max_trades_per_day=args.max_trades_day,
                         swap_long=swap_in_price(spec, "long", ref_price) if spec else 0.0,
                         swap_short=swap_in_price(spec, "short", ref_price) if spec else 0.0)
        cut = int(len(df) * args.split)
        train = df.iloc[:cut].reset_index(drop=True)
        for strat in strategies:
            p0, risk_mult, _ = sb.apply_preset(preset, strat, base)
            risk = args.risk * risk_mult
            p, st_in, _ = sb.select_best(train, p0, risk)
            if p is None:
                log.append(f"  {tf:>3} {strat:<9} : pas assez de trades en apprentissage")
                continue
            log.append(f"  {tf:>3} {strat:<9} apprentissage : {sb.fmt(st_in)}")
            # Le test final doit pouvoir atteindre le minimum de trades exige,
            # sinon il est "gache" : l'indice serait desactive quel que soit son avantage.
            projected = st_in["trades"] * (1 - args.split) / args.split
            if projected < sb.CRITERIA["trades"][0]:
                log.append(f"      ecarte : ~{projected:.0f} trades attendus sur le test final "
                           f"(minimum {sb.CRITERIA['trades'][0]}) -> historique trop court pour cette UT")
                continue
            if best is None or st_in["t_stat"] > best[0]:
                best = (st_in["t_stat"], p, tf, df, risk, st_in)

    if best is None:
        return False, None, log + ["  => aucune combinaison exploitable"]

    _, p, tf, df, risk, st_in = best
    cut = int(len(df) * args.split)
    test = df.iloc[cut:].reset_index(drop=True)
    st_out = sb.evaluate(test, p, risk)
    ok, lines = sb.verdict(st_out)
    log.append(f"  CHOIX (sur l'apprentissage) : {tf} {p.strategy}")
    log.append(f"  test final, jamais vu : {sb.fmt(st_out)}")
    log += ["  " + x for x in lines]
    log.append(f"  => {'ACTIVE' if ok else 'DESACTIVE'}")

    keys = ["tf", "strategy"] + list(sb.GRIDS[p.strategy])
    values = {"tf": tf, "strategy": p.strategy, **{k: getattr(p, k) for k in sb.GRIDS[p.strategy]},
              "expected_R": round(st_out.get("expectancy_R", 0.0), 3)}
    return ok, {k: values[k] for k in keys} | {"expected_R": values["expected_R"]}, log


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folder", help="dossier SyntX_data exporte par ExportBars")
    ap.add_argument("--out", default=sb.PRESET_FILE, help="fichier de calibration a produire")
    ap.add_argument("--risk", type=float, default=0.5, help="risque de base par trade en %%")
    ap.add_argument("--split", type=float, default=0.7, help="part d'apprentissage (le reste = test final)")
    ap.add_argument("--spread", type=float, default=0.0, help="forcer un spread en unites de prix")
    ap.add_argument("--spike-slippage", type=float, default=1.0)
    ap.add_argument("--max-trades-day", type=int, default=20, help="doit egaler InpMaxTradesPerDay de l'EA")
    ap.add_argument("--keep-failed", action="store_true",
                    help="ecrire les reglages des indices non valides (ils restent desactives)")
    args = ap.parse_args()

    files = sorted(glob.glob(os.path.join(args.folder, "*.csv")))
    files = [f for f in files if os.path.basename(f) != "SyntX_specs.csv"]
    if not files:
        sys.exit(f"Aucun CSV dans {args.folder}")
    specs = load_specs(args.folder)
    if not specs:
        print("ATTENTION : SyntX_specs.csv absent -> spread et swap reels inconnus.\n")

    rows: list[tuple[str, str, object]] = []
    summary = []
    for label, fam, level in ALLOWED:
        name = f"{label} {level}"
        mine = [f for f in files if sb.detect_index(f) == (fam, level) and sb.detect_tf(f)]
        print(f"=== {name} ===")
        if not mine:
            print("  aucune donnee -> DESACTIVE\n")
            rows.append((name, "enabled", 0))
            summary.append((name, "-", "-", float("nan"), "DESACTIVE (pas de donnees)"))
            continue
        ok, values, log = calibrate_index(label, fam, level, mine, specs.get(f"{fam}{level}", {}), args)
        print("\n".join(log) + "\n")
        rows.append((name, "enabled", int(ok)))
        if values and (ok or args.keep_failed):
            for k, v in values.items():
                if k != "expected_R":
                    rows.append((name, k, v))
        summary.append((name, values["tf"] if values else "-", values["strategy"] if values else "-",
                        values["expected_R"] if values else float("nan"),
                        "ACTIVE" if ok else "DESACTIVE"))

    sb.write_overrides(args.out, rows)
    print("=== Resume ===")
    for name, tf, strat, e, state in summary:
        e_txt = "" if math.isnan(e) else f"E test = {e:+.3f}R"
        print(f"  {name:<11} {tf:>3} {strat:<9} {e_txt:<16} {state}")
    n_on = sum(1 for s in summary if s[4] == "ACTIVE")
    print(f"\n{n_on} indice(s) active(s). Fichier ecrit : {args.out}")
    print("Copiez-le dans Common\\Files de MT5 ; l'EA le lit au demarrage.")
    if n_on == 0:
        print("Aucun indice ne passe : sur ces donnees, aucun avantage exploitable n'a ete trouve.")


if __name__ == "__main__":
    main()
