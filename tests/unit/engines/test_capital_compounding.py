import tempfile
import unittest
from pathlib import Path

from katarina.contracts.runtime import EventEnvelope
from katarina.engines.account_risk_state import AccountRiskCoordinator, AccountRiskStateEngine
from katarina.engines.broker_risk import BrokerNativeRiskBook
from katarina.engines.capital import CapitalCompoundingEngine, Kat1CapitalCompoundingRuntime
from katarina.engines.execution_recovery import ManagementRecoveryCoordinator
from katarina.engines.manual_risk import SharedAccountRiskEngine
from katarina.engines.position import RRProfitTracker
from katarina.engines.risk import RiskGovernor
from katarina.engines.sizing import PositionSizingEngine
from katarina.memory.runtime_state import RuntimeStatePersistence
from katarina.memory.store import MemoryStore
from katarina.validation.engine import ValidationDisposition, ValidationResult


def accepted(topic,payload):
    return ValidationResult(EventEnvelope(topic,payload),ValidationDisposition.ACCEPT,(),1)


class CapitalCompoundingTests(unittest.TestCase):
    def test_100_to_200_saves_thirty_percent_and_next_target_280(self):
        c=CapitalCompoundingEngine()
        c.initialize(100)
        e=c.observe_balance(200)
        s=c.snapshot()
        self.assertTrue(e.milestone_triggered)
        self.assertAlmostEqual(s.reserve_balance,60)
        self.assertAlmostEqual(s.active_balance,140)
        self.assertAlmostEqual(s.next_target_balance,280)

    def test_second_milestone_rebalances_reserve_to_30_percent_of_total_not_additive(self):
        c=CapitalCompoundingEngine()
        c.initialize(100)
        c.observe_balance(200)
        c.observe_balance(280)
        s=c.snapshot()
        self.assertEqual(s.milestone_count,2)
        self.assertAlmostEqual(s.reserve_balance,84)
        self.assertAlmostEqual(s.active_balance,196)
        self.assertAlmostEqual(s.next_target_balance,392)

    def test_profit_between_milestones_is_active_but_target_stays_fixed(self):
        c=CapitalCompoundingEngine()
        c.initialize(100); c.observe_balance(200)
        c.observe_balance(250)
        s=c.snapshot()
        self.assertAlmostEqual(s.reserve_balance,60)
        self.assertAlmostEqual(s.active_balance,190)
        self.assertAlmostEqual(s.next_target_balance,280)

    def test_withdrawal_within_reserve_does_not_reduce_active_or_rebase_target(self):
        c=CapitalCompoundingEngine()
        c.initialize(100); c.observe_balance(200)
        e=c.apply_external_flow(-30,balance_after=170)
        s=c.snapshot()
        self.assertAlmostEqual(e.reserve_used,30)
        self.assertAlmostEqual(s.reserve_balance,30)
        self.assertAlmostEqual(s.active_balance,140)
        self.assertAlmostEqual(s.next_target_balance,280)

    def test_withdrawal_exceeding_reserve_recalculates_active_and_target(self):
        c=CapitalCompoundingEngine()
        c.initialize(100); c.observe_balance(200)
        e=c.apply_external_flow(-100,balance_after=100)
        s=c.snapshot()
        self.assertAlmostEqual(e.reserve_used,60)
        self.assertAlmostEqual(e.active_used,40)
        self.assertAlmostEqual(s.reserve_balance,0)
        self.assertAlmostEqual(s.active_balance,100)
        self.assertAlmostEqual(s.next_target_balance,200)

    def test_no_reserve_withdrawal_rebases_to_remaining_balance(self):
        c=CapitalCompoundingEngine()
        c.initialize(100)
        c.apply_external_flow(-50,balance_after=50)
        s=c.snapshot()
        self.assertAlmostEqual(s.active_balance,50)
        self.assertAlmostEqual(s.next_target_balance,100)

    def test_deposit_is_external_capital_not_fake_profit(self):
        c=CapitalCompoundingEngine()
        c.initialize(100)
        c.apply_external_flow(100,balance_after=200)
        s=c.snapshot()
        self.assertEqual(s.milestone_count,0)
        self.assertAlmostEqual(s.reserve_balance,0)
        self.assertAlmostEqual(s.active_balance,200)
        self.assertAlmostEqual(s.next_target_balance,400)

    def test_floating_equity_does_not_trigger_milestone(self):
        c=CapitalCompoundingEngine()
        rt=Kat1CapitalCompoundingRuntime(c)
        rt.observe(accepted("account.state",{
            "account_currency_digits":2,
            "balance_units":10000,
            "equity_units":20000,
        }))
        self.assertEqual(c.snapshot().milestone_count,0)
        rt.observe(accepted("account.state",{
            "account_currency_digits":2,
            "balance_units":10000,
            "equity_units":30000,
        }))
        self.assertEqual(c.snapshot().milestone_count,0)

    def test_kat1_realized_balance_triggers_milestone(self):
        c=CapitalCompoundingEngine()
        rt=Kat1CapitalCompoundingRuntime(c)
        rt.observe(accepted("account.state",{"account_currency_digits":2,"balance_units":10000,"equity_units":10000}))
        rt.observe(accepted("account.state",{"account_currency_digits":2,"balance_units":20000,"equity_units":20000}))
        self.assertAlmostEqual(c.snapshot().reserve_balance,60)

    def test_kat1_withdrawal_uses_reserve_first(self):
        c=CapitalCompoundingEngine()
        rt=Kat1CapitalCompoundingRuntime(c)
        rt.observe(accepted("account.state",{"account_currency_digits":2,"balance_units":10000,"equity_units":10000}))
        rt.observe(accepted("account.state",{"account_currency_digits":2,"balance_units":20000,"equity_units":20000}))
        rt.observe(accepted("account.ledger",{"ledger_kind":2,"amount_units":-3000}))
        rt.observe(accepted("account.state",{"account_currency_digits":2,"balance_units":17000,"equity_units":17000}))
        self.assertAlmostEqual(c.snapshot().reserve_balance,30)
        self.assertAlmostEqual(c.snapshot().active_balance,140)

    def test_sizing_uses_active_balance_not_total_balance(self):
        r=PositionSizingEngine().size_active(
            active_balance=140,current_equity=200,risk_fraction=.05,
            stop_distance=10,value_per_price_unit_per_lot=10,
            volume_min=.01,volume_max=10,volume_step=.01,
        )
        self.assertTrue(r.valid)
        self.assertAlmostEqual(r.risk_cash,7.0)

    def test_equity_is_safety_ceiling_below_active_balance(self):
        r=PositionSizingEngine().size_active(
            active_balance=140,current_equity=100,risk_fraction=.05,
            stop_distance=10,value_per_price_unit_per_lot=10,
            volume_min=.01,volume_max=10,volume_step=.01,
        )
        self.assertAlmostEqual(r.risk_cash,5.0)

    def test_risk_coordinator_rebases_existing_cash_risk_to_active_capital(self):
        c=CapitalCompoundingEngine(); c.initialize(100); c.observe_balance(200)
        # Position has $7 cash risk = 5% of active $140.
        from katarina.engines.manual_risk import PositionRiskInput, SymbolRiskSpec
        p=PositionRiskInput("p","KATARINA","BUY",.007,2000,2000,1990,SymbolRiskSpec(.01,1.0))
        positions=SharedAccountRiskEngine().assess([p],equity=200)
        state=AccountRiskStateEngine(max_open_risk=.08)
        coord=AccountRiskCoordinator(state,RiskGovernor(max_open_risk=.08,hard_per_trade=.05),capital=c)
        out=coord.authorize_and_reserve(
            positions,reservation_id="r",day_key="d",requested_fraction=.05,
            uncertainty=.1,expected_rr=2,health_ok=True,reconciled=True,
        )
        self.assertAlmostEqual(out.state.risk_capital,140)
        self.assertAlmostEqual(out.state.position_risk_fraction,.05)
        self.assertAlmostEqual(out.approved_fraction,.03)

    def test_capital_state_persists_across_restart(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/"k.db"
            capital=CapitalCompoundingEngine(); capital.initialize(100); capital.observe_balance(200)
            ar=AccountRiskStateEngine(); rr=RRProfitTracker(); ex=ManagementRecoveryCoordinator(); br=BrokerNativeRiskBook()
            with MemoryStore(path) as store:
                RuntimeStatePersistence(store).save_components(
                    account_risk=ar,rr_tracker=rr,execution_recovery=ex,broker_risk=br,capital=capital
                )
            restored=CapitalCompoundingEngine()
            ar2=AccountRiskStateEngine(); rr2=RRProfitTracker(); ex2=ManagementRecoveryCoordinator(); br2=BrokerNativeRiskBook()
            with MemoryStore(path) as store:
                self.assertTrue(RuntimeStatePersistence(store).restore_components(
                    account_risk=ar2,rr_tracker=rr2,execution_recovery=ex2,broker_risk=br2,capital=restored
                ))
            self.assertAlmostEqual(restored.snapshot().reserve_balance,60)
            self.assertAlmostEqual(restored.snapshot().active_balance,140)
            self.assertAlmostEqual(restored.snapshot().next_target_balance,280)


if __name__=="__main__": unittest.main()
