"""Fail-closed historical cost and timeframe comparison checks."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR=Path(__file__).resolve().parents[3]/"scripts"/"research"
sys.path.insert(0,str(SCRIPT_DIR))
from historical_cost_profile import profile
from compare_historical_timeframes import compare


def proposal(cost=.1,side="BUY"):
    return dict(symbol="DEMO",side=side,
         entry_spread_atr=cost,cost_screen_pass=cost<=.15,
         quoted_markout_bps=3.0,midpoint_markout_bps=5.0)

def observed(report_type,period=None,signals=None):
    if period is None: period=dict(start="2026-10-01",end_exclusive="2026-10-10")
    if signals is None: signals=[proposal()]
    data=dict(report_version=report_type,period=period,
        symbols=[dict(symbol="DEMO",signals=signals,
                      m1_bars_available=100,m5_bars_available=100)],
        signals_observed=len(signals),live_execution_enabled=False)
    return data

class HistoricalCostTests(unittest.TestCase):
    def test_profile_remains_descriptive(self):
        row=observed("historical_tick_shadow_v1",signals=[proposal(.1),proposal(2.0)])
        with tempfile.TemporaryDirectory() as tmp:
            file=Path(tmp)/"ticks.json"
            file.write_text(json.dumps(row))
            report=profile([file])
        self.assertEqual(report["total_observations"],2)
        self.assertEqual(report["total_spread_pass"],1)
        self.assertFalse(report["selection_permitted"])
        self.assertAlmostEqual(report["groups"][0]["spread_atr_median"],1.05)

    def test_tampered_spread_gate_fails(self):
        row=observed("historical_tick_shadow_v1")
        row["symbols"][0]["signals"][0]["cost_screen_pass"]=False
        with tempfile.TemporaryDirectory() as tmp:
            file=Path(tmp)/"bad.json"
            file.write_text(json.dumps(row))
            with self.assertRaisesRegex(ValueError,"original_spread_gate_mismatch"):
                profile([file])

    def test_matching_windows_can_be_diagnosed_not_promoted(self):
        one=observed("historical_tick_shadow_v1")
        five=observed("historical_m5_m15_shadow_v1")
        result=compare(one,five)
        self.assertEqual(result["symbol_count"],1)
        self.assertEqual(result["timeframe_profiles"]["M1_M5"]["spread_qualified"],1)
        self.assertFalse(result["model_promotion_allowed"])
        self.assertTrue(result["different_signal_populations"])

    def test_mismatched_windows_and_symbols_rejected(self):
        one=observed("historical_tick_shadow_v1")
        five=observed("historical_m5_m15_shadow_v1")
        five["period"]["end_exclusive"]="2026-10-11"
        with self.assertRaisesRegex(ValueError,"non_matching_calendar_windows"):
            compare(one,five)
        five["period"]["end_exclusive"]="2026-10-10"
        five["symbols"][0]["symbol"]="OTHER"
        with self.assertRaisesRegex(ValueError,"unmatched_symbol_universe"):
            compare(one,five)

    def test_modified_live_gate_rejected(self):
        one=observed("historical_tick_shadow_v1")
        five=observed("historical_m5_m15_shadow_v1")
        five["live_execution_enabled"]=True
        with self.assertRaisesRegex(ValueError,"cannot_compare_live_results"):
            compare(one,five)


if __name__=="__main__":
    unittest.main()
