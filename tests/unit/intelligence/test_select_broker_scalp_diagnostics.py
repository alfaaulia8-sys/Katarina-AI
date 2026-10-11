"""Group selection and broker output audits must not promote overfitted results."""
import sys,unittest
from pathlib import Path
SCRIPTS=Path(__file__).resolve().parents[3]/"scripts"/"research"
sys.path.insert(0,str(SCRIPTS))
from select_broker_scalp_diagnostics import compare,summary
from audit_broker_scalp_setups import check

def event(phase="development_aug",status="CLOSED",R=.2,side="BUY"):
    return dict(phase=phase,symbol="XAUUSD.vx",family="ema20_trend_reclaim_v2",
        side=side,tp_atr=1.5,sl_atr=1,
        adverse_slippage_each_side_ticks=1,status=status,
        R=R,usd_minlot=R,
        signal_close_utc="2026-08-19T12:00:00+00:00",
        entry_time_utc="2026-08-19T12:00:01+00:00",
        trade_filled=False,strategy_live_authorized=False)

class SelectionTests(unittest.TestCase):
    def test_chronological_labels_do_not_promote_unproven_setup(self):
        entries=[event(phase="development_aug") for _ in range(20)]
        entries += [event(phase="development_sep") for _ in range(20)]
        entries += [event(phase="diagnostic_oct",R=99) for _ in range(20)]
        dataset=dict(report_version="broker_aware_independent_strategy_tick_study_v1",
            live_execution_enabled=False,model_promotion_allowed=False,
            result_count=len(entries),trials=entries)
        result=compare(dataset)
        self.assertEqual(result["decision"],"NO_TRADE")
        self.assertFalse(result["has_development_pass"])
        self.assertFalse(result["model_promotion_allowed"])

    def test_positive_October_cannot_override_negative_August(self):
        rows=[event("development_aug",R=-1)]
        rows+=[event("development_sep",R=1)]
        rows+=[event("diagnostic_oct",R=100)]
        dataset=dict(report_version="broker_aware_independent_strategy_tick_study_v1",
            live_execution_enabled=False,model_promotion_allowed=False,
            result_count=len(rows),trials=rows)
        chosen=compare(dataset)["all_combinations"][0]
        self.assertFalse(chosen["development_pass"])

    def test_summary_includes_loss_and_drawdown(self):
        rows=[event(R=2),event(R=-1)]
        result=summary(rows)
        self.assertAlmostEqual(result["mean_r"],.5)
        self.assertAlmostEqual(result["profit_factor"],2.)
        self.assertAlmostEqual(result["max_drawdown_r"],1.)

    def test_broker_auditor_rejects_forged_live_permissions(self):
        dataset=dict(report_version="broker_aware_independent_strategy_tick_study_v1",
                     live_execution_enabled=True,model_promotion_allowed=False,
                     result_count=0,trials=[],summaries=[])
        with self.assertRaisesRegex(ValueError,"unauthorized_trading_status"):
            check(dataset)

if __name__=="__main__":
    unittest.main()
