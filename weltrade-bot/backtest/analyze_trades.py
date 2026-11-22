#!/usr/bin/env python3
"""
Analyse du journal de trades ecrit par SyntX Guardian v2.

Le fichier se trouve dans le dossier commun de MetaTrader :
  MT5 > Fichier > Ouvrir le dossier des donnees > remonter d'un niveau >
  Common > Files > SyntX_Guardian_trades.csv

Calcule, pour chaque indice et pour l'ensemble, les memes statistiques que
le backtester (en R), verifie les seuils minimaux, et compare si besoin au
gain moyen attendu du backtest.

Exemples :
  python analyze_trades.py SyntX_Guardian_trades.csv
  python analyze_trades.py SyntX_Guardian_trades.csv --risk 0.5 --expected "FX Vol 40=0.15"
"""
from __future__ import annotations

import argparse
import sys

import pandas as pd

from syntx_backtest import N_FOLDS, fmt, stats_from_r, verdict


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("journal", help="SyntX_Guardian_trades.csv")
    ap.add_argument("--risk", type=float, default=0.5, help="risque par trade en %% (courbe d'equity)")
    ap.add_argument("--expected", action="append", default=[],
                    help="gain moyen attendu du backtest, ex. 'FX Vol 40=0.15' (repetable)")
    ap.add_argument("--since", help="ne garder que les trades depuis cette date (AAAA-MM-JJ)")
    args = ap.parse_args()

    df = pd.read_csv(args.journal)
    if df.empty:
        sys.exit("Journal vide.")
    df["exit_time"] = pd.to_datetime(df["exit_time"].astype(str).str.replace(".", "-", regex=False))
    if args.since:
        df = df[df["exit_time"] >= pd.Timestamp(args.since)]
    df = df[df["risk"] > 0]   # trades sans risque enregistre : non comparables en R

    expected = {}
    for item in args.expected:
        name, _, val = item.partition("=")
        expected[name.strip().lower()] = float(val)

    days = max((df["exit_time"].max() - df["exit_time"].min()).days, 1)
    print(f"Journal : {len(df)} trades sur {days} jours "
          f"({df['exit_time'].min():%Y-%m-%d} -> {df['exit_time'].max():%Y-%m-%d})")
    print(f"Profit total : {df['profit'].sum():+.2f} (devise du compte)\n")

    for (preset, strat), g in df.groupby(["preset", "strategy"]):
        st = stats_from_r(g["r"].to_numpy(dtype=float), args.risk)
        parts = [g["r"].iloc[k * len(g) // N_FOLDS:(k + 1) * len(g) // N_FOLDS] for k in range(N_FOLDS)]
        st["stable_folds"] = sum(int(len(x) > 0 and x.mean() > 0) for x in parts)
        print(f"=== {preset} | {strat} | {g['timeframe'].iloc[0]} ===")
        print(fmt(st))
        reasons = g["exit_reason"].value_counts().to_dict()
        print(f"  sorties : {reasons}")
        exp = expected.get(str(preset).lower())
        if exp is not None:
            ecart = (st["expectancy_R"] - exp) / abs(exp) * 100 if exp else float("nan")
            ok = abs(ecart) <= 30
            print(f"  backtest attendu E={exp:+.3f}R -> ecart {ecart:+.0f}% "
                  f"({'coherent' if ok else 'ECART TROP GRAND : revoir le reglage'})")
        ok, lines = verdict(st)
        print(f"  => {'VALIDE' if ok else 'NON VALIDE'}")
        for line in lines:
            print("  " + line)
        print()

    st = stats_from_r(df["r"].to_numpy(dtype=float), args.risk)
    print("=== Ensemble du portefeuille ===")
    print(fmt(st))


if __name__ == "__main__":
    main()
