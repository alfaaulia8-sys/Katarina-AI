import unittest

from katarina.contracts.runtime import EventEnvelope
from katarina.engines.account_risk_state import AccountRiskCoordinator, AccountRiskStateEngine
from katarina.engines.capital import CapitalCompoundingEngine, Kat1CapitalCompoundingRuntime
from katarina.engines.manual_risk import SharedAccountRiskEngine
from katarina.engines.risk import RiskGovernor
from katarina.validation.engine import ValidationDisposition, ValidationResult


def accepted(topic,payload):
    return ValidationResult(EventEnvelope(topic,payload),ValidationDisposition.ACCEPT,(),1)


class CapitalCompoundingPipelineTests(unittest.TestCase):
    def test_balance_100_to_200_changes_risk_basis_to_150(self):
        capital=CapitalCompoundingEngine()
        rt=Kat1CapitalCompoundingRuntime(capital)
        rt.observe(accepted("account.state",{"account_currency_digits":2,"balance_units":10000,"equity_units":10000}))
        rt.observe(accepted("account.state",{"account_currency_digits":2,"balance_units":20000,"equity_units":20000}))

        positions=SharedAccountRiskEngine().assess([],equity=200)
        state=AccountRiskStateEngine(max_open_risk=.08)
        coord=AccountRiskCoordinator(state,RiskGovernor(max_open_risk=.08,hard_per_trade=.05),capital=capital)
        out=coord.authorize_and_reserve(
            positions,reservation_id="trade-a",day_key="d",requested_fraction=.05,
            uncertainty=.1,expected_rr=2,health_ok=True,reconciled=True,
        )
        self.assertAlmostEqual(out.state.risk_capital,150)
        self.assertAlmostEqual(out.approved_fraction,.05)

    def test_withdrawal_excess_rebases_next_trade_capital(self):
        capital=CapitalCompoundingEngine()
        rt=Kat1CapitalCompoundingRuntime(capital)
        rt.observe(accepted("account.state",{"account_currency_digits":2,"balance_units":10000,"equity_units":10000}))
        rt.observe(accepted("account.state",{"account_currency_digits":2,"balance_units":20000,"equity_units":20000}))
        rt.observe(accepted("account.ledger",{"ledger_kind":2,"amount_units":-10000}))
        rt.observe(accepted("account.state",{"account_currency_digits":2,"balance_units":10000,"equity_units":10000}))
        self.assertAlmostEqual(capital.snapshot().active_balance,100)
        self.assertAlmostEqual(capital.snapshot().next_target_balance,200)


if __name__=="__main__": unittest.main()
