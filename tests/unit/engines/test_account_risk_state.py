import unittest

from katarina.engines.account_risk_state import (
    AccountRiskCoordinator,
    AccountRiskStateEngine,
    DailyDrawdownTracker,
    Kat1AccountRiskStateRuntime,
    Kat1PendingOrderRiskRuntime,
    PendingOrderRiskInput,
)
from katarina.engines.manual_risk import SharedAccountRiskEngine, SymbolRiskSpec
from katarina.engines.risk import RiskAction, RiskGovernor
from katarina.contracts.runtime import EventEnvelope
from katarina.validation.engine import ValidationDisposition, ValidationResult


class AccountRiskStateTests(unittest.TestCase):
    def setUp(self):
        self.positions=SharedAccountRiskEngine().assess([],equity=10000)
        self.spec=SymbolRiskSpec(.01,1.0)

    def test_pending_order_consumes_risk_budget(self):
        e=AccountRiskStateEngine()
        e.observe_equity("2026-10-06",10000)
        e.upsert_pending(PendingOrderRiskInput("o1","KATARINA","BUY",.5,2000,1994,self.spec))
        s=e.assess(self.positions)
        self.assertAlmostEqual(s.pending_risk_fraction,.03)
        d=RiskGovernor().evaluate_state(s,requested_fraction=.05,uncertainty=.1,expected_rr=2,health_ok=True,reconciled=True)
        self.assertEqual(d.action,RiskAction.APPROVE)
        self.assertAlmostEqual(d.approved_fraction,.05)

    def test_pending_plus_reservation_prevents_concurrent_overallocation(self):
        e=AccountRiskStateEngine()
        e.observe_equity("2026-10-06",10000)
        e.upsert_pending(PendingOrderRiskInput("o1","KATARINA","BUY",.5,2000,1994,self.spec))
        e.reservations.reserve("decision-2",.05)
        s=e.assess(self.positions)
        self.assertAlmostEqual(s.total_committed_risk_fraction,.08)
        d=RiskGovernor().evaluate_state(s,requested_fraction=.01,uncertainty=.1,expected_rr=2,health_ok=True,reconciled=True)
        self.assertEqual(d.action,RiskAction.REJECT)

    def test_bind_pending_releases_pre_submit_reservation(self):
        e=AccountRiskStateEngine()
        e.observe_equity("2026-10-06",10000)
        e.reservations.reserve("r1",.03)
        e.bind_pending(PendingOrderRiskInput("o1","KATARINA","BUY",.5,2000,1994,self.spec),reservation_id="r1")
        s=e.assess(self.positions)
        self.assertAlmostEqual(s.reserved_risk_fraction,0)
        self.assertAlmostEqual(s.pending_risk_fraction,.03)

    def test_manual_pending_without_sl_is_unbounded(self):
        e=AccountRiskStateEngine()
        e.observe_equity("2026-10-06",10000)
        e.upsert_pending(PendingOrderRiskInput("manual","MANUAL_MOBILE","BUY",.1,2000,None,self.spec))
        s=e.assess(self.positions)
        self.assertTrue(s.has_unbounded_risk)
        d=RiskGovernor().evaluate_state(s,requested_fraction=.01,uncertainty=.1,expected_rr=2,health_ok=True,reconciled=True)
        self.assertEqual(d.action,RiskAction.PAUSE)

    def test_daily_drawdown_cash_flow_neutrality(self):
        d=DailyDrawdownTracker(limit=.10)
        d.start_day("d",1000)
        d.apply_cash_flow("d",-100,equity_after=900)
        self.assertAlmostEqual(d.snapshot().max_drawdown_fraction,0)
        d.observe("d",810)
        self.assertAlmostEqual(d.snapshot().max_drawdown_fraction,.10)
        self.assertTrue(d.snapshot().halted)

    def test_daily_halt_does_not_clear_on_intraday_recovery(self):
        d=DailyDrawdownTracker(limit=.10)
        d.start_day("d",1000)
        d.observe("d",890)
        d.observe("d",1000)
        self.assertTrue(d.snapshot().halted)
        self.assertGreaterEqual(d.snapshot().max_drawdown_fraction,.10)

    def test_new_day_resets_daily_lock(self):
        d=DailyDrawdownTracker(limit=.10)
        d.start_day("d1",1000); d.observe("d1",890)
        d.observe("d2",890)
        self.assertFalse(d.snapshot().halted)
        self.assertEqual(d.snapshot().day_key,"d2")

    def test_state_round_trip(self):
        e=AccountRiskStateEngine()
        e.observe_equity("d",10000)
        e.reservations.reserve("r1",.02)
        e.upsert_pending(PendingOrderRiskInput("o1","KATARINA","BUY",.5,2000,1994,self.spec))
        state=e.snapshot_state()
        r=AccountRiskStateEngine(); r.restore_state(state)
        s=r.assess(self.positions)
        self.assertAlmostEqual(s.total_committed_risk_fraction,.05)

    def test_atomic_authorize_and_reserve_limits_second_signal(self):
        e=AccountRiskStateEngine()
        c=AccountRiskCoordinator(e,RiskGovernor(max_open_risk=.08,hard_per_trade=.05))
        first=c.authorize_and_reserve(
            self.positions,reservation_id="a",day_key="d",requested_fraction=.05,
            uncertainty=.1,expected_rr=2,health_ok=True,reconciled=True,
        )
        second=c.authorize_and_reserve(
            self.positions,reservation_id="b",day_key="d",requested_fraction=.05,
            uncertainty=.1,expected_rr=2,health_ok=True,reconciled=True,
        )
        self.assertAlmostEqual(first.approved_fraction,.05)
        self.assertAlmostEqual(second.approved_fraction,.03)
        self.assertAlmostEqual(e.reservations.total_fraction,.08)

    def test_kat1_pending_order_is_automatically_counted(self):
        e=AccountRiskStateEngine(); rt=Kat1PendingOrderRiskRuntime(e)
        def accepted(topic,payload):
            return ValidationResult(EventEnvelope(topic,payload),ValidationDisposition.ACCEPT,(),1)
        rt.observe(accepted("account.state",{"account_currency_digits":2}))
        rt.observe(accepted("symbol.spec",{
            "instrument_id":1,"spec_revision":1,"price_scale":2,"volume_scale":2,
            "tick_size_units":1,"tick_value_loss_units":100,
        }))
        rt.observe(accepted("order.state",{
            "broker_order_ticket":99,"change_kind":1,"entry_type":3,
            "normalized_order_state":2,"instrument_id":1,"origin_class":3,
            "side":1,"volume_current_units":50,"price_open_units":200000,
            "sl_units":199400,
        }))
        e.observe_equity("d",10000)
        state=e.assess(self.positions)
        self.assertAlmostEqual(state.pending_risk_fraction,.03)
        self.assertAlmostEqual(state.external_pending_risk_fraction,.03)

    def test_kat1_filled_or_removed_pending_order_releases_risk(self):
        e=AccountRiskStateEngine(); rt=Kat1PendingOrderRiskRuntime(e)
        def accepted(topic,payload):
            return ValidationResult(EventEnvelope(topic,payload),ValidationDisposition.ACCEPT,(),1)
        rt.observe(accepted("account.state",{"account_currency_digits":2}))
        rt.observe(accepted("symbol.spec",{
            "instrument_id":1,"spec_revision":1,"price_scale":2,"volume_scale":2,
            "tick_size_units":1,"tick_value_loss_units":100,
        }))
        base={"broker_order_ticket":99,"change_kind":1,"entry_type":3,
              "normalized_order_state":2,"instrument_id":1,"origin_class":1,
              "side":1,"volume_current_units":50,"price_open_units":200000,"sl_units":199400}
        rt.observe(accepted("order.state",base))
        rt.observe(accepted("order.state",{**base,"normalized_order_state":4}))
        self.assertEqual(len(e.pending),0)

    def test_kat1_withdrawal_does_not_create_fake_daily_drawdown(self):
        e=AccountRiskStateEngine(); rt=Kat1AccountRiskStateRuntime(e)
        def accepted(topic,payload,ts=1_780_000_000_000_000_000):
            return ValidationResult(EventEnvelope(topic,payload,source_time_ns=ts),ValidationDisposition.ACCEPT,(),1)
        rt.observe(accepted("account.state",{"account_currency_digits":2,"equity_units":100000}))
        rt.observe(accepted("account.ledger",{"ledger_kind":2,"amount_units":-10000}))
        rt.observe(accepted("account.state",{"account_currency_digits":2,"equity_units":90000}))
        self.assertAlmostEqual(e.daily.snapshot().max_drawdown_fraction,0.0)

    def test_kat1_commission_is_not_neutralized_as_cash_flow(self):
        e=AccountRiskStateEngine(); rt=Kat1AccountRiskStateRuntime(e)
        def accepted(topic,payload,ts=1_780_000_000_000_000_000):
            return ValidationResult(EventEnvelope(topic,payload,source_time_ns=ts),ValidationDisposition.ACCEPT,(),1)
        rt.observe(accepted("account.state",{"account_currency_digits":2,"equity_units":100000}))
        rt.observe(accepted("account.ledger",{"ledger_kind":7,"amount_units":-10000}))
        rt.observe(accepted("account.state",{"account_currency_digits":2,"equity_units":90000}))
        self.assertAlmostEqual(e.daily.snapshot().max_drawdown_fraction,.10)


if __name__=="__main__": unittest.main()
