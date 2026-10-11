"""Session filtering must only use pre-observed closed-signal metadata."""
import sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]/"scripts"/"research"
sys.path.insert(0,str(ROOT))
from diagnose_session_regime_setups import examine,FILTERS

def item(phase="development_aug",hour=9,r=-.2):
    return dict(phase=phase,symbol="XAUUSD.vx",
        family="liquidity_sweep_reclaim_v2",side="SELL",
        adverse_slippage_each_side_ticks=1,tp_atr=2.,sl_atr=1.,
        status="CLOSED",R=r,
        signal_close_utc="2026-08-19T{:02}:00:00+00:00".format(hour),
        context_adx=19.,volume_ratio=1.3)

class SessionRegimeTests(unittest.TestCase):
    def test_sessions_apply_only_same_signal_timestamp(self):
        a=item(hour=9)
        self.assertTrue(FILTERS["london_newyork"](a))
        self.assertTrue(FILTERS["sweep_range_active"](a))
        self.assertFalse(FILTERS["newyork_trend_active"](a))

    def test_one_profitable_history_sample_never_promotes(self):
        records=[item("development_aug",9,2.),
                 item("development_sep",9,2.),
                 item("diagnostic_oct",9,2.)]
        result=examine(dict(report_version=
             "broker_aware_independent_strategy_tick_study_v1",
             live_execution_enabled=False,trials=records))
        self.assertFalse(result["model_promotion_allowed"])
        self.assertFalse(result["live_execution_enabled"])
        self.assertEqual(result["positive_development_cases"],[])

    def test_live_input_rejected(self):
        with self.assertRaisesRegex(ValueError,"live_not_disabled"):
            examine(dict(report_version=
                "broker_aware_independent_strategy_tick_study_v1",
                live_execution_enabled=True,trials=[]))

if __name__=="__main__":
    unittest.main()
