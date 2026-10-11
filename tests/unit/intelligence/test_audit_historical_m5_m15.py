"""M5/M15 historical evidence must be chronological and read-only."""
import json,sys,tempfile,unittest
from datetime import datetime,timedelta,timezone
from pathlib import Path

SCRIPTS=Path(__file__).resolve().parents[3]/"scripts"/"research"
sys.path.insert(0,str(SCRIPTS))
from audit_historical_m5_m15 import inspect

T=datetime(2026,10,8,12,tzinfo=timezone.utc)

def document():
    signal=dict(symbol="DEMO",family="trend_impulse_break_m5_m15_v1",
      side="BUY",regime="TREND_UP",
      signal_bar_close_utc=T.isoformat(),
      context_bar_close_utc=(T-timedelta(minutes=15)).isoformat(),
      entry_tick_utc=(T+timedelta(seconds=1)).isoformat(),
      exit_tick_utc=(T+timedelta(seconds=901)).isoformat(),
      entry_bid=100.,entry_ask=100.1,exit_bid=100.2,exit_ask=100.3,
      signal_atr=2.,entry_spread_atr=.05,cost_screen_pass=True,
      quoted_markout_bps=.1/100.05*10000,
      m5_evidence_sha256="a"*64,m15_evidence_sha256="b"*64,
      is_realized_pnl=False,live_risk_authorized=False)
    return dict(report_version="historical_m5_m15_shadow_v1",
       live_execution_enabled=False,model_promotion_allowed=False,
       signal_timeframe="M5",context_timeframe="M15",
       period=dict(start="2026-10-08",end_exclusive="2026-10-09"),
       symbols_scanned=1,signals_observed=1,
       symbols=[dict(symbol="DEMO",current_trade_mode=4,signals=[signal])])

class M5IntegrityTests(unittest.TestCase):
    def evaluate(self,obj):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"m5.json"
            path.write_text(json.dumps(obj))
            return inspect([path])

    def test_research_is_not_promotion(self):
        result=self.evaluate(document())
        self.assertEqual(result["spread_pass"],1)
        self.assertTrue(result["context_timestamp_verified"])
        self.assertFalse(result["model_promotion_allowed"])

    def test_future_context_rejected(self):
        obj=document()
        obj["symbols"][0]["signals"][0]["context_bar_close_utc"]=(
            T+timedelta(minutes=1)).isoformat()
        with self.assertRaisesRegex(ValueError,"lookahead_context"):
            self.evaluate(obj)

    def test_corrupt_fill_math_rejected(self):
        obj=document()
        obj["symbols"][0]["signals"][0]["quoted_markout_bps"]+=10
        with self.assertRaisesRegex(ValueError,"corrupt_markout"):
            self.evaluate(obj)

    def test_spread_gate_cannot_be_relaxed(self):
        obj=document()
        obj["symbols"][0]["signals"][0]["cost_screen_pass"]=False
        with self.assertRaisesRegex(ValueError,"corrupt_spread_gate"):
            self.evaluate(obj)

    def test_missing_context_fingerprint_rejected(self):
        obj=document()
        obj["symbols"][0]["signals"][0]["m15_evidence_sha256"]="missing"
        with self.assertRaisesRegex(ValueError,"missing_frame_fingerprint"):
            self.evaluate(obj)

if __name__=="__main__":
    unittest.main()
