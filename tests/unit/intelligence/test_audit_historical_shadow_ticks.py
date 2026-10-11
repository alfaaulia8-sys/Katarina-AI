"""Guard historical replay arithmetic against fabricated future fills."""
from datetime import datetime,timezone,timedelta
import json,runpy,tempfile,unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
AUDIT=runpy.run_path(str(ROOT/"scripts/research/audit_historical_shadow_ticks.py"))["audit"]
UTC=timezone.utc
START=datetime(2026,10,8,10,tzinfo=UTC)


def example():
    signal=dict(
        symbol="DEMO",side="BUY",cost_screen_pass=True,
        signal_bar_close_utc=START.isoformat(),
        entry_tick_utc=(START+timedelta(seconds=1)).isoformat(),
        exit_tick_utc=(START+timedelta(seconds=901)).isoformat(),
        entry_bid=100.0,entry_ask=100.2,
        exit_bid=100.5,exit_ask=100.7,
        quoted_markout_bps=(100.5-100.2)/100.1*10000,
        is_realized_pnl=False,live_risk_authorized=False
    )
    return dict(report_version="historical_tick_shadow_v1",
                live_execution_enabled=False,model_promotion_allowed=False,
                signals_observed=1,period={"start":"2026-10-08","end_exclusive":"2026-10-09"},
                symbols=[dict(symbol="DEMO",m1_bars_available=300,signals=[signal])])


class AuditHistoricalTests(unittest.TestCase):
    def verify(self,obj):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"history.json"
            path.write_text(json.dumps(obj))
            return AUDIT([path])

    def test_genuine_quote_markout_is_descriptive(self):
        result=self.verify(example())
        self.assertEqual(result["signals"],1)
        self.assertFalse(result["model_promotion_allowed"])
        self.assertEqual(result["group_summary"][0]["observations"],1)

    def test_forbid_future_or_before_close_entry(self):
        obj=example()
        obj["symbols"][0]["signals"][0]["entry_tick_utc"] = (
            START-timedelta(seconds=5)).isoformat()
        with self.assertRaises(ValueError):
            self.verify(obj)

    def test_forbid_exit_before_horizon(self):
        obj=example()
        obj["symbols"][0]["signals"][0]["exit_tick_utc"] = (
            START+timedelta(seconds=800)).isoformat()
        with self.assertRaises(ValueError):
            self.verify(obj)

    def test_detect_modified_markout_math(self):
        obj=example()
        obj["symbols"][0]["signals"][0]["quoted_markout_bps"]+=5
        with self.assertRaises(ValueError):
            self.verify(obj)

    def test_live_authorization_fails(self):
        obj=example()
        obj["live_execution_enabled"]=True
        with self.assertRaises(ValueError):
            self.verify(obj)


if __name__=="__main__":
    unittest.main()
