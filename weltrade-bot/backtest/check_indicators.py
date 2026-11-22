#!/usr/bin/env python3
"""
Verifie que le backtester calcule les indicateurs EXACTEMENT comme MT5.

ExportBars ecrit, pour un indice FX/SFX Vol en M15, les valeurs que MT5
calcule lui-meme (ATR 14, ADX Wilder 14, RSI 14, Bollinger 20/2, EMA 20)
dans SyntX_data/indicators_<symbole>_M15.txt. Ce script recalcule ces
indicateurs en Python sur les memes barres et compare.

Si un ecart depasse la tolerance, les resultats du backtest ne
correspondent pas a l'EA : ne vous fiez pas a la calibration avant
correction.

  python check_indicators.py "<Dossier commun>/Files/SyntX_data"
"""
from __future__ import annotations

import glob
import os
import sys

import numpy as np
import pandas as pd

import syntx_backtest as sb

# Tolerances : relatives pour les prix (ATR, Bollinger, EMA),
# absolues en points d'indicateur pour ADX et RSI (echelle 0-100).
TOL_REL = 0.005
TOL_ABS = 0.5
WARMUP = 300   # premieres valeurs ignorees (initialisation des moyennes)


def compare(bars_path: str, ind_path: str) -> bool:
    bars = sb.load_csv(bars_path)
    ind = pd.read_csv(ind_path)
    ind["time"] = pd.to_datetime(ind["time"].astype(str).str.replace(".", "-", regex=False))

    mid, up, lo = sb.bollinger(bars["close"], 20, 2.0)
    py = pd.DataFrame({
        "time": bars["time"],
        "atr14": sb.atr(bars, 14),
        "adxw14": sb.adx(bars, 14),
        "rsi14": sb.rsi(bars["close"], 14),
        "bb_mid": mid, "bb_up": up, "bb_lo": lo,
        "ema20": sb.ema(bars["close"], 20),
    })
    m = ind.merge(py, on="time", suffixes=("_mt5", "_py")).iloc[WARMUP:]
    if len(m) < 100:
        print(f"  trop peu de barres communes ({len(m)}) : exportez plus d'historique")
        return False

    ok_all = True
    for col in ("atr14", "adxw14", "rsi14", "bb_mid", "bb_up", "bb_lo", "ema20"):
        a, b = m[f"{col}_mt5"].to_numpy(), m[f"{col}_py"].to_numpy()
        if col in ("adxw14", "rsi14"):
            err = float(np.nanmax(np.abs(a - b)))
            ok = err <= TOL_ABS
            txt = f"ecart max {err:.3f} points (tolerance {TOL_ABS})"
        else:
            err = float(np.nanmax(np.abs(a - b) / np.maximum(np.abs(a), 1e-12)))
            ok = err <= TOL_REL
            txt = f"ecart max {err * 100:.3f} % (tolerance {TOL_REL * 100:.1f} %)"
        ok_all &= ok
        print(f"  [{'OK ' if ok else 'NON'}] {col:<7} {txt}")
    return ok_all


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    folder = sys.argv[1]
    dumps = glob.glob(os.path.join(folder, "indicators_*.txt"))
    if not dumps:
        sys.exit("Aucun fichier indicators_*.txt : relancez ExportBars (version 2).")
    ok_all = True
    for ind_path in dumps:
        base = os.path.basename(ind_path)[len("indicators_"):-len(".txt")]
        bars_path = os.path.join(folder, base + ".csv")
        print(f"=== {base} ===")
        if not os.path.exists(bars_path):
            print(f"  barres introuvables : {bars_path}")
            ok_all = False
            continue
        ok_all &= compare(bars_path, ind_path)
    print("\nIndicateurs IDENTIQUES a MT5." if ok_all else
          "\nECART DETECTE : envoyez ce resultat, le backtester doit etre corrige avant de calibrer.")
    sys.exit(0 if ok_all else 1)


if __name__ == "__main__":
    main()
