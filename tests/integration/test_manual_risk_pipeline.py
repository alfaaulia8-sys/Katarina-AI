import unittest

from katarina.contracts.runtime import EventEnvelope
from katarina.engines.manual_risk import Kat1SharedAccountRiskRuntime
from katarina.engines.risk import RiskAction, RiskGovernor
from katarina.validation.engine import ValidationDisposition, ValidationResult


def accepted(topic, payload):
    return ValidationResult(EventEnvelope(topic,payload),ValidationDisposition.ACCEPT,(),1)


class ManualRiskPipelineTests(unittest.TestCase):
    def _runtime(self, *, sl_units=199400):
        rt=Kat1SharedAccountRiskRuntime()
        rt.observe(accepted("account.state",{
            "equity_units":1000000,
            "account_currency_digits":2,
        }))
        rt.observe(accepted("symbol.spec",{
            "instrument_id":1,
            "spec_revision":1,
            "price_scale":2,
            "volume_scale":2,
            "tick_size_units":1,
            "tick_value_loss_units":100,
        }))
        rt.observe(accepted("position.state",{
            "position_identifier":1001,
            "instrument_id":1,
            "spec_revision":1,
            "change_kind":1,
            "origin_class":3,
            "side":1,
            "volume_units":50,
            "open_price_units":200000,
            "current_price_units":200000,
            "sl_units":sl_units,
        }))
        return rt

    def test_manual_kat1_position_consumes_account_risk_capacity(self):
        account=self._runtime().assessment()
        decision=RiskGovernor(max_open_risk=.08,hard_per_trade=.05).evaluate_account(
            account,
            requested_fraction=.05,
            drawdown_fraction=0,
            daily_drawdown_fraction=0,
            uncertainty=.1,
            expected_rr=2,
            health_ok=True,
            reconciled=True,
        )
        self.assertAlmostEqual(account.external_risk_fraction,.03)
        self.assertEqual(decision.action,RiskAction.APPROVE)
        self.assertAlmostEqual(decision.approved_fraction,.05)

    def test_manual_kat1_position_without_sl_stops_auto_entry(self):
        account=self._runtime(sl_units=0).assessment()
        decision=RiskGovernor().evaluate_account(
            account,
            requested_fraction=.01,
            drawdown_fraction=0,
            daily_drawdown_fraction=0,
            uncertainty=.1,
            expected_rr=2,
            health_ok=True,
            reconciled=True,
        )
        self.assertTrue(account.has_unbounded_risk)
        self.assertEqual(decision.action,RiskAction.PAUSE)
        self.assertEqual(decision.reason,"unbounded_open_risk")


if __name__=="__main__":
    unittest.main()
