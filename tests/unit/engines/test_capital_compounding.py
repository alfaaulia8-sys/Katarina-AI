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
    def test_100_to_200_locks_25pct_total_realized_balance_next_400(self):
        c=CapitalCompoundingEngine()
        c.initialize(100)
        e=c.observe_balance(200)
        s=c.snapshot()
        self.assertTrue(e.milestone_triggered)
        self.assertAlmostEqual(s.reserve_balance,50)
        self.assertAlmostEqual(s.active_balance,150)
        self.assertAlmostEqual(s.next_target_balance,400)

    def test_second_balance_doubling_locks_25pct_of_total(self):
        c=CapitalCompoundingEngine()
        c.initialize(100)
        c.observe_balance(200)
        c.observe_balance(400)
        s=c.snapshot()
        self.assertEqual(s.milestone_count,2)
        self.assertAlmostEqual(s.reserve_balance,150)  # previous 50 + new 100
        self.assertAlmostEqual(s.active_balance,250)
        self.assertAlmostEqual(s.next_target_balance,800)

    def test_owner_approved_10k_20k_40k_80k_cumulative_lock(self):
        c = CapitalCompoundingEngine()
        c.initialize(10_000)
        for balance, locked, active in (
            (20_000, 5_000, 15_000),
            (40_000, 15_000, 25_000),
            (80_000, 35_000, 45_000),
        ):
            e = c.observe_balance(balance)
            self.assertTrue(e.milestone_triggered)
            self.assertAlmostEqual(c.snapshot().reserve_balance, locked)
            self.assertAlmostEqual(c.snapshot().active_balance, active)
            # Repeated broker snapshots must NOT reserve the same milestone twice.
            self.assertFalse(c.observe_balance(balance).milestone_triggered)
            self.assertAlmostEqual(c.snapshot().reserve_balance, locked)
        self.assertEqual(c.snapshot().milestone_count, 3)

    def test_restart_preserves_cumulative_lock_without_double_trigger(self):
        c = CapitalCompoundingEngine()
        c.initialize(10_000)
        c.observe_balance(20_000)
        c.observe_balance(40_000)
        persisted = c.snapshot_state()
        restarted = CapitalCompoundingEngine()
        restarted.restore_state(persisted)
        self.assertFalse(restarted.observe_balance(40_000).milestone_triggered)
        self.assertAlmostEqual(restarted.snapshot().reserve_balance, 15_000)
        restarted.observe_balance(80_000)
        self.assertAlmostEqual(restarted.snapshot().reserve_balance, 35_000)

    def test_withdrawal_consumes_cumulative_lock_before_active_capital(self):
        c = CapitalCompoundingEngine()
        c.initialize(10_000)
        c.observe_balance(20_000)
        c.observe_balance(40_000)
        e = c.apply_external_flow(-5_000, balance_after=35_000)
        self.assertAlmostEqual(e.reserve_used, 5_000)
        self.assertAlmostEqual(e.active_used, 0)
        self.assertAlmostEqual(c.snapshot().reserve_balance, 10_000)
        self.assertAlmostEqual(c.snapshot().active_balance, 25_000)

    def test_snapshot_crosses_multiple_realized_balance_milestones(self):
        c=CapitalCompoundingEngine()
        c.initialize(100)
        c.observe_balance(450)
        s=c.snapshot()
        self.assertEqual(s.milestone_count,2)
        self.assertAlmostEqual(s.reserve_balance,112.5)
        self.assertAlmostEqual(s.next_target_balance,800)

    def test_profit_between_milestones_is_active_but_target_stays_fixed(self):
        c=CapitalCompoundingEngine()
        c.initialize(100); c.observe_balance(200)
        c.observe_balance(250)
        s=c.snapshot()
        self.assertAlmostEqual(s.reserve_balance,50)
        self.assertAlmostEqual(s.active_balance,200)
        self.assertAlmostEqual(s.next_target_balance,400)

    def test_withdrawal_within_reserve_does_not_reduce_active_or_rebase_target(self):
        c=CapitalCompoundingEngine()
        c.initialize(100); c.observe_balance(200)
        e=c.apply_external_flow(-30,balance_after=170)
        s=c.snapshot()
        self.assertAlmostEqual(e.reserve_used,30)
        self.assertAlmostEqual(s.reserve_balance,20)
        self.assertAlmostEqual(s.active_balance,150)
        self.assertAlmostEqual(s.next_target_balance,400)

    def test_withdrawal_exceeding_reserve_recalculates_active_and_target(self):
        c=CapitalCompoundingEngine()
        c.initialize(100); c.observe_balance(200)
        e=c.apply_external_flow(-100,balance_after=100)
        s=c.snapshot()
        self.assertAlmostEqual(e.reserve_used,50)
        self.assertAlmostEqual(e.active_used,50)
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

    def test_deposit_after_loss_does_not_lower_cashflow_adjusted_hwm(self):
        c=CapitalCompoundingEngine()
        c.initialize(100)
        c.observe_balance(200)
        c.observe_balance(180)
        c.apply_external_flow(100,balance_after=280)
        s=c.snapshot()
        self.assertAlmostEqual(s.reserve_balance,50)
        self.assertAlmostEqual(s.next_target_balance,500)
        self.assertEqual(s.milestone_count,1)
        c.observe_balance(499)
        self.assertEqual(c.snapshot().milestone_count,1)
        c.observe_balance(500)
        self.assertEqual(c.snapshot().milestone_count,2)
        self.assertAlmostEqual(c.snapshot().reserve_balance,175)  # old 50 + 25% of 500

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
        self.assertAlmostEqual(c.snapshot().reserve_balance,50)

    def test_kat1_withdrawal_uses_reserve_first(self):
        c=CapitalCompoundingEngine()
        rt=Kat1CapitalCompoundingRuntime(c)
        rt.observe(accepted("account.state",{"account_currency_digits":2,"balance_units":10000,"equity_units":10000}))
        rt.observe(accepted("account.state",{"account_currency_digits":2,"balance_units":20000,"equity_units":20000}))
        rt.observe(accepted("account.ledger",{"ledger_kind":2,"amount_units":-3000}))
        rt.observe(accepted("account.state",{"account_currency_digits":2,"balance_units":17000,"equity_units":17000}))
        self.assertAlmostEqual(c.snapshot().reserve_balance,20)
        self.assertAlmostEqual(c.snapshot().active_balance,150)

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
        # Position risk $7; locked reserve 25% leaves $150 active.
        from katarina.engines.manual_risk import PositionRiskInput, SymbolRiskSpec
        p=PositionRiskInput("p","KATARINA","BUY",.007,2000,2000,1990,SymbolRiskSpec(.01,1.0))
        positions=SharedAccountRiskEngine().assess([p],equity=200)
        state=AccountRiskStateEngine(max_open_risk=.08)
        coord=AccountRiskCoordinator(state,RiskGovernor(max_open_risk=.08,hard_per_trade=.05),capital=c)
        out=coord.authorize_and_reserve(
            positions,reservation_id="r",day_key="d",requested_fraction=.05,
            uncertainty=.1,expected_rr=2,health_ok=True,reconciled=True,
        )
        self.assertAlmostEqual(out.state.risk_capital,150)
        self.assertAlmostEqual(out.state.position_risk_fraction,7/150)
        self.assertAlmostEqual(out.approved_fraction,.08-7/150)

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
            self.assertAlmostEqual(restored.snapshot().reserve_balance,50)
            self.assertAlmostEqual(restored.snapshot().active_balance,150)
            self.assertAlmostEqual(restored.snapshot().next_target_balance,400)


    def test_restore_rejects_corrupt_state_without_mutating_current_capital(self):
        c=CapitalCompoundingEngine()
        c.initialize(100)
        c.observe_balance(200)
        safe=c.snapshot_state()
        for key,bad in (
            ("total_balance",float("nan")),
            ("active_balance",5),
            ("reserve_balance",400),
            ("next_target_balance",float("inf")),
            ("milestone_count",-2),
            ("reserve_fraction",float("nan")),
            ("growth_multiple",float("nan")),
            ("initialized","yes"),
        ):
            with self.subTest(field=key):
                corrupt=dict(safe)
                corrupt[key]=bad
                with self.assertRaises(ValueError):
                    c.restore_state(corrupt)
                self.assertEqual(c.snapshot_state(),safe)

    def test_legacy_30pct_preview_keeps_protected_reserve_and_rebases_milestone(self):
        old=CapitalCompoundingEngine(reserve_fraction=.30)
        old.initialize(100)
        old.observe_balance(200)
        original=old.snapshot_state()
        proposed=CapitalCompoundingEngine.preview_legacy_migration(original)
        self.assertEqual(old.snapshot_state(),original)
        self.assertAlmostEqual(proposed["reserve_fraction"],.25)
        self.assertAlmostEqual(proposed["reserve_balance"],60)
        self.assertAlmostEqual(proposed["active_balance"],140)
        self.assertAlmostEqual(proposed["next_target_balance"],400)
        new=CapitalCompoundingEngine()
        new.restore_state(proposed)
        self.assertAlmostEqual(new.snapshot().reserve_balance,60)
        self.assertAlmostEqual(new.snapshot().next_target_balance,400)
        # Migration is OFFLINE ONLY, never silently applied at restart.
        new.observe_balance(399)
        self.assertEqual(new.snapshot().milestone_count,1)
        new.observe_balance(400)
        self.assertEqual(new.snapshot().milestone_count,2)
        self.assertAlmostEqual(new.snapshot().reserve_balance,160)  # preserved legacy 60 + new 100

    def test_legacy_preview_rejects_incoherent_or_new_state(self):
        old=CapitalCompoundingEngine(reserve_fraction=.30)
        old.initialize(100)
        old.observe_balance(200)
        state=old.snapshot_state()
        for changed in (
            {"active_balance":500},
            {"reserve_fraction":.25},
            {"reserve_balance":float("nan")},
            {"last_milestone_balance":float("inf")},
        ):
            with self.subTest(mod=changed):
                with self.assertRaisesRegex(ValueError,"invalid_legacy"):
                    CapitalCompoundingEngine.preview_legacy_migration(
                        {**state,**changed}
                    )


if __name__=="__main__": unittest.main()
