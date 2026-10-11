"""Merged brokerage study provenance and selection test."""
import sys,tempfile,json,unittest
from pathlib import Path

SCRIPTS=Path(__file__).resolve().parents[3]/"scripts"/"research"
sys.path.insert(0,str(SCRIPTS))
from merge_broker_scalp_studies import merge

class MergeTests(unittest.TestCase):
    def _write(self,root,name):
        result=dict(report_version="broker_aware_independent_strategy_tick_study_v1",
          live_execution_enabled=False,model_promotion_allowed=False,
          symbol_scope=[name],date_windows_utc=[["development_aug","2026-08-16","2026-09-01"]],
          decision_latency_seconds=.25,maximum_quote_wait_seconds=30,
          max_historical_spread_atr=.5,adverse_slippage_each_side_ticks=[0,1,3],
          hypothetical_exit_grid=[[1.0,1.0]],hold_seconds=1800,
          broker=dict(broker_company="Valetax International Limited"),
          trials=[],result_count=0,summaries=[],per_scan={})
        file=Path(root)/(name+".json")
        file.write_text(json.dumps(result))
        return str(file)

    def test_disjoint_broker_batches_combine_without_trade_activation(self):
        with tempfile.TemporaryDirectory() as temp:
            a=self._write(temp,"XAUUSD.vx")
            b=self._write(temp,"NAS100.vx")
            result=merge([a,b])
        self.assertEqual(result["symbol_scope"],["NAS100.vx","XAUUSD.vx"])
        self.assertTrue(result["merge_is_read_only"])
        self.assertFalse(result["model_promotion_allowed"])

    def test_repeated_symbol_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            a=self._write(temp,"XAUUSD.vx")
            with self.assertRaisesRegex(ValueError,"duplicate_broker_symbol"):
                merge([a,a])

if __name__=="__main__":
    unittest.main()
