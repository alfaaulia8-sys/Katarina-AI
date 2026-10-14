import unittest

from katarina.contracts.runtime import EventEnvelope
from katarina.engines.manual_risk import Kat1SharedAccountRiskRuntime
from katarina.engines.risk import (
    RiskAction, RiskGovernor, OwnerDrawdownTracker, DrawdownMode,
    DrawdownAuthority,
)
from katarina.adapters.mt5_account_pnl import Mt5ReadOnlyPnLAdapter
from katarina.engines.manual_risk import SharedAccountRiskEngine
from katarina.engines.account_risk_state import (
    AccountRiskCoordinator, AccountRiskStateEngine,
)
from tests.unit.adapters.test_mt5_account_pnl import FakeMt5, position, deal, BEFORE, AFTER
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

    def test_realized_and_floating_broker_loss_never_unlocks_extreme_without_provenance(self):
        broker=FakeMt5()
        adapter=Mt5ReadOnlyPnLAdapter(broker,katarina_magic=99001)
        previous=adapter.capture(captured_utc_ns=BEFORE)
        broker.equity=6000
        broker.positions=[position(profit=-4000)]
        current=adapter.capture(captured_utc_ns=AFTER)
        observed=adapter.reconcile(previous,current)
        self.assertTrue(observed.attribution.balanced)
        self.assertAlmostEqual(observed.attribution.owner_loss_cash,4000)
        self.assertFalse(observed.broker_history_complete_verified)

        tracker=OwnerDrawdownTracker()
        tracker.observe("broker-day",0,hwm_cash=10000)
        attribution=tracker.observe(
            "broker-day",.40,hwm_cash=10000,
            owner_loss_cash=observed.attribution.owner_loss_cash,
            katarina_loss_cash=observed.attribution.katarina_loss_cash,
            reconciled=observed.broker_history_complete_verified,
        )
        self.assertEqual(attribution.mode,DrawdownMode.EMERGENCY_LOCKDOWN)
        state=AccountRiskStateEngine()
        state.observe_equity("broker-day",10000)
        account=SharedAccountRiskEngine().assess([],equity=6000)
        decision=AccountRiskCoordinator(state).authorize_and_reserve(
            account,reservation_id="forbidden-extreme",
            day_key="broker-day",requested_fraction=.01,
            uncertainty=.1,expected_rr=2,health_ok=True,reconciled=True,
            entry_kind="EXTREME_RECOVERY",
            drawdown_authority=DrawdownAuthority(
                "broker-day",DrawdownMode.EXTREME_SURVIVAL,.40,True,True,
            ),
        )
        self.assertFalse(decision.reserved)
        self.assertEqual(decision.reason,"broker_origin_pnl_adapter_not_authenticated")

    def test_owner_manual_close_does_not_reclassify_katarina_dd35_loss(self):
        broker=FakeMt5()
        broker.equity=6600
        broker.positions=[position(reason=3,magic=99001,profit=-400)]
        adapter=Mt5ReadOnlyPnLAdapter(broker,katarina_magic=99001)
        previous=adapter.capture(captured_utc_ns=BEFORE)
        broker.equity=6400
        broker.positions=[]
        broker.deals=[deal(entry=1,reason=0,profit=-600)]
        current=adapter.capture(captured_utc_ns=AFTER)
        observed=adapter.reconcile(previous,current)
        self.assertTrue(observed.attribution.balanced)
        self.assertEqual(observed.attribution.owner_loss_cash,0)
        self.assertEqual(observed.attribution.katarina_loss_cash,200)
        tracker=OwnerDrawdownTracker()
        tracker.observe("broker-day",.34,hwm_cash=10000)
        authority=tracker.observe(
            "broker-day",.36,hwm_cash=10000,
            owner_loss_cash=observed.attribution.owner_loss_cash,
            katarina_loss_cash=observed.attribution.katarina_loss_cash,
            reconciled=observed.broker_history_complete_verified,
        )
        self.assertEqual(authority.mode,DrawdownMode.EMERGENCY_LOCKDOWN)
        self.assertFalse(authority.owner_caused)

    def test_katarina_same_day_lockdown_survives_account_recovery(self):
        tracker = OwnerDrawdownTracker()
        tracker.observe("broker-day", .20, hwm_cash=10000, reconciled=True)
        entered = tracker.observe(
            "broker-day", .36, hwm_cash=10000,
            katarina_loss_cash=1600, reconciled=True,
        )
        self.assertEqual(entered.mode, DrawdownMode.EMERGENCY_LOCKDOWN)
        recovery = tracker.observe(
            "broker-day", .12, hwm_cash=10000, reconciled=True,
        )
        self.assertEqual(recovery.mode, DrawdownMode.EMERGENCY_LOCKDOWN)
        account = SharedAccountRiskEngine().assess([], equity=8800)
        decision = RiskGovernor().evaluate_account(
            account, requested_fraction=.01,
            drawdown_fraction=.12, daily_drawdown_fraction=.12,
            uncertainty=.1, expected_rr=2,
            health_ok=True, reconciled=True,
            trading_day_key="broker-day", drawdown_authority=recovery,
        )
        self.assertEqual(decision.action, RiskAction.PAUSE)
        self.assertEqual(decision.approved_fraction, 0)

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
