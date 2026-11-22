"""
Tests automatiques de SyntX Guardian.

  python -m pytest backtest/test_syntx.py -q

Verifient que :
  - les presets de l'EA (LoadPreset) et du backtester (PRESETS) sont identiques ;
  - les cles du fichier de calibration sont comprises par l'EA ;
  - le backtest ne regarde jamais dans le futur (pas de "look-ahead") ;
  - sur un marche equitable, aucune strategie ne gagne (outil non biaise) ;
  - un avantage reel est detecte.
"""
from __future__ import annotations

import os
import re

import numpy as np
import pytest

import syntx_backtest as sb

HERE = os.path.dirname(os.path.abspath(__file__))
EA = os.path.join(HERE, "..", "mt5", "SyntX_Guardian.mq5")
NUM = r"\s*([-\d.]+)\s*"


def ea_source() -> str:
    with open(EA, encoding="utf-8") as fh:
        return fh.read()


def test_vol_presets_match_ea():
    src = ea_source()
    pat = re.compile(r'SetVol\("([^"]+)",\s*InpTF_(\w+),\s*InpS_\w+,' + ",".join([NUM] * 12) + r"\)")
    found = pat.findall(src)
    assert len(found) == 6, "6 presets FX/SFX attendus dans LoadPreset()"
    tf_defaults = dict(re.findall(r"input ENUM_TIMEFRAMES InpTF_(\w+)\s*=\s*PERIOD_(\w+);", src))
    keys = ["risk_mult", "fast", "slow", "adx_min", "sl_atr", "tp_atr", "trail_atr", "brk_period",
            "bb_dev", "rsi_low", "adx_max_mr", "mr_sl_atr"]
    for name, tf_input, *vals in found:
        fam, lvl = sb.detect_index(name)
        py = sb.PRESETS[(fam, lvl)]
        assert py["tf"] == tf_defaults[tf_input], f"UT differente pour {name}"
        for k, v in zip(keys, vals):
            assert float(v) == pytest.approx(float(py[k])), f"{name} : {k} EA={v} Python={py[k]}"


def test_gainx_presets_match_ea():
    src = ea_source()
    pat = re.compile(r'SetDrift\("GainX (\d+)",' + ",".join([NUM] * 7) + r"\)")
    found = pat.findall(src)
    assert len(found) == 5
    for lvl, *vals in found:
        py = sb.PRESETS[("GAINX", int(lvl))]
        expected = [py["risk_mult"], py["lookback"], py["drift_ema"], py["cooldown"],
                    py["sl_spike"], py["tp_spike"], py["max_bars"]]
        assert [float(v) for v in vals] == pytest.approx([float(x) for x in expected]), f"GainX {lvl}"


def test_calibration_keys_understood_by_ea():
    src = ea_source()
    body = src[src.index("bool SetCalibratedValue"):src.index("int ApplyCalibration")]
    ea_keys = set(re.findall(r'key == "(\w+)"', body)) | {"enabled"}
    assert ea_keys == set(sb.OVERRIDE_KEYS)


def test_overrides_roundtrip(tmp_path):
    path = tmp_path / sb.PRESET_FILE
    sb.write_overrides(str(path), [("FX Vol 40", "enabled", 1), ("FX Vol 40", "strategy", "breakout"),
                                   ("FX Vol 40", "brk_period", 40), ("FX Vol 40", "sl_atr", 3.5)])
    ov = sb.load_overrides(str(path))["fx vol 40"]
    preset = sb.apply_overrides(sb.PRESETS[("FXVOL", 40)], ov)
    p, _, _ = sb.apply_preset(preset, None, sb.Params())
    assert (p.strategy, p.brk_period, p.sl_atr) == ("breakout", 40, 3.5)
    assert isinstance(p.brk_period, int)


@pytest.mark.parametrize("strategy", ["ema_cross", "breakout", "meanrev", "drift"])
def test_no_lookahead(strategy):
    """Les trades clos avant la barre k doivent etre identiques avec ou sans
    les donnees posterieures a k."""
    if strategy == "drift":
        df = sb.simulate("gainx", 12000, seed=3)
        preset = sb.PRESETS[("GAINX", 400)]
    else:
        df = sb.resample(sb.simulate("fxvol", 120000, seed=3), "15min")
        preset = sb.PRESETS[("FXVOL", 40)]
    p, _, _ = sb.apply_preset(preset, strategy, sb.Params(spread=0.1))
    k = int(len(df) * 0.6)
    full = sb.backtest(df, p).trades
    cut = sb.backtest(df.iloc[:k].reset_index(drop=True), p).trades
    full_before = [t for t in full if t[1] < k - 1]
    cut_before = [t for t in cut if t[1] < k - 1]
    assert len(full_before) > 5
    assert full_before == cut_before


def test_fair_market_has_no_edge():
    """Sans spread, sur un marche equitable, le gain moyen reste proche de 0."""
    es = []
    for seed in (21, 22, 23):
        df = sb.resample(sb.simulate("fxvol", 200000, seed=seed), "15min")
        for strat in ("ema_cross", "breakout", "meanrev"):
            p, _, _ = sb.apply_preset(sb.PRESETS[("FXVOL", 40)], strat, sb.Params())
            r = sb.backtest(df, p).trades_r
            es.extend(r)
    assert abs(np.mean(es)) < 0.08


def test_real_edge_is_detected():
    df = sb.simulate("gainx", 80000, seed=4, edge=0.3)
    p, _, _ = sb.apply_preset(sb.PRESETS[("GAINX", 999)], None, sb.Params(spread=0.3))
    st = sb.evaluate(df, p, 0.5)
    ok, _ = sb.verdict(st)
    assert ok


def test_spread_filter_blocks_trades():
    df = sb.resample(sb.simulate("fxvol", 100000, seed=5), "15min")
    p, _, _ = sb.apply_preset(sb.PRESETS[("FXVOL", 40)], "breakout", sb.Params(spread=0.0))
    n_ok = len(sb.backtest(df, p).trades)
    p_wide, _, _ = sb.apply_preset(sb.PRESETS[("FXVOL", 40)], "breakout", sb.Params(spread=1e6))
    assert n_ok > 0 and len(sb.backtest(df, p_wide).trades) == 0


def test_daily_trade_cap_matches_ea():
    """Comme l'EA : jamais plus de max_trades_per_day entrees par jour."""
    df = sb.simulate("gainx", 20000, seed=6)
    p, _, _ = sb.apply_preset(sb.PRESETS[("GAINX", 400)], None, sb.Params(max_trades_per_day=5))
    res = sb.backtest(df, p)
    days = df["time"].dt.normalize().to_numpy()
    per_day = {}
    for entry_i, *_ in res.trades:
        per_day[days[entry_i]] = per_day.get(days[entry_i], 0) + 1
    assert per_day and max(per_day.values()) <= 5


def test_overrides_file_uses_crlf(tmp_path):
    path = tmp_path / sb.PRESET_FILE
    sb.write_overrides(str(path), [("GainX 999", "enabled", 1)])
    assert open(path, "rb").read().count(b"\r\n") == 2
