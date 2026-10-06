import unittest

from katarina.contracts.runtime import EventEnvelope
from katarina.engines.manual_risk import (
    Kat1SharedAccountRiskRuntime,
    PositionRiskInput,
    SharedAccountRiskEngine,
    SharedAccountRiskTracker,
    SymbolRiskSpec,
)
from katarina.engines.risk import RiskAction, RiskGovernor, RiskRequest
from katarina.validation.engine import (
    ValidationDisposition,
    ValidationResult,
)


SPEC = SymbolRiskSpec(tick_size=0.01, tick_value_loss=1.0)


def manual(
    position_id="m1",
    *,
    origin="MANUAL_MOBILE",
    side="BUY",
    volume=.5,
    open_price=2000.0,
    current_price=2000.0,
    stop_loss=1994.0,
    broker_loss_to_sl=None,
    symbol_spec=SPEC,
):
    return PositionRiskInput(
        position_id=position_id,
        origin=origin,
        side=side,
        volume=volume,
        open_price=open_price,
        current_price=current_price,
        stop_loss=stop_loss,
        symbol_spec=symbol_spec,
        broker_loss_to_sl=broker_loss_to_sl,
    )


def accepted(topic, payload):
    return ValidationResult(
        EventEnvelope(topic,payload),
        ValidationDisposition.ACCEPT,
        (),
        1,
    )


class ManualAccountRiskTests(unittest.TestCase):
    def setUp(self):
        self.engine=SharedAccountRiskEngine()
        self.gov=RiskGovernor(max_open_risk=.08,hard_per_trade=.05)

    def test_manual_trade_risk_is_included(self):
        a=self.engine.assess([manual()],equity=10000)
        self.assertAlmostEqual(a.external_risk_cash,300.0)
        self.assertAlmostEqual(a.external_risk_fraction,.03)
        self.assertAlmostEqual(a.open_risk_fraction,.03)
        self.assertFalse(a.has_unbounded_risk)

    def test_kat1_numeric_origin_and_side_are_supported(self):
        a=self.engine.assess([manual(origin=3,side=1)],equity=10000)
        self.assertAlmostEqual(a.external_risk_fraction,.03)
        self.assertEqual(a.position_risks[0].origin,"MANUAL_MOBILE")

    def test_three_percent_manual_plus_five_percent_katarina_fills_eight_percent_cap(self):
        a=self.engine.assess([manual()],equity=10000)
        d=self.gov.evaluate_account(
            a,requested_fraction=.05,drawdown_fraction=0,daily_drawdown_fraction=0,
            uncertainty=.1,expected_rr=2,health_ok=True,reconciled=True,
        )
        self.assertEqual(d.action,RiskAction.APPROVE)
        self.assertAlmostEqual(d.approved_fraction,.05)

    def test_six_percent_manual_reduces_new_katarina_risk_to_two_percent(self):
        a=self.engine.assess([manual(volume=1.0)],equity=10000)
        d=self.gov.evaluate_account(
            a,requested_fraction=.05,drawdown_fraction=0,daily_drawdown_fraction=0,
            uncertainty=.1,expected_rr=2,health_ok=True,reconciled=True,
        )
        self.assertEqual(d.action,RiskAction.REDUCE)
        self.assertAlmostEqual(d.approved_fraction,.02)

    def test_manual_without_sl_blocks_new_automated_risk(self):
        a=self.engine.assess([manual(stop_loss=None)],equity=10000)
        d=self.gov.evaluate_account(
            a,requested_fraction=.01,drawdown_fraction=0,daily_drawdown_fraction=0,
            uncertainty=.1,expected_rr=2,health_ok=True,reconciled=True,
        )
        self.assertEqual(d.action,RiskAction.PAUSE)
        self.assertEqual(d.reason,"unbounded_open_risk")

    def test_partial_close_reduces_risk_immediately(self):
        before=self.engine.assess([manual(volume=.5)],equity=10000)
        after=self.engine.assess([manual(volume=.25)],equity=10000)
        self.assertAlmostEqual(after.open_risk_cash,before.open_risk_cash/2)

    def test_tracker_upsert_partial_close_and_remove(self):
        tracker=SharedAccountRiskTracker()
        tracker.upsert(manual(position_id="ticket",volume=.5))
        self.assertAlmostEqual(tracker.assess(equity=10000).open_risk_fraction,.03)
        tracker.upsert(manual(position_id="ticket",volume=.25))
        self.assertAlmostEqual(tracker.assess(equity=10000).open_risk_fraction,.015)
        tracker.remove("ticket")
        self.assertEqual(tracker.assess(equity=10000).position_count,0)

    def test_multiple_manual_origins_are_aggregated(self):
        a=self.engine.assess([
            manual("desktop",origin="MANUAL_DESKTOP",volume=.25),
            manual("mobile",origin="MANUAL_MOBILE",volume=.25),
            manual("web",origin="MANUAL_WEB",volume=.25),
        ],equity=10000)
        self.assertEqual(a.external_position_count,3)
        self.assertAlmostEqual(a.external_risk_cash,450.0)

    def test_foreign_ea_and_unknown_are_risk_aware(self):
        a=self.engine.assess([
            manual("foreign",origin="FOREIGN_EA",volume=.25),
            manual("unknown",origin="UNKNOWN",volume=.25),
        ],equity=10000)
        self.assertEqual(a.external_position_count,2)

    def test_katarina_and_manual_both_count_toward_total_open_risk(self):
        a=self.engine.assess([
            manual("manual",origin="MANUAL_MOBILE",volume=.5),
            manual("katarina",origin="KATARINA",volume=.25),
        ],equity=10000)
        self.assertAlmostEqual(a.external_risk_cash,300.0)
        self.assertAlmostEqual(a.open_risk_cash,450.0)

    def test_broker_ordercalcprofit_value_is_preferred(self):
        a=self.engine.assess([manual(broker_loss_to_sl=275.0,symbol_spec=None)],equity=10000)
        self.assertAlmostEqual(a.open_risk_cash,275.0)

    def test_missing_symbol_spec_without_broker_calc_blocks(self):
        a=self.engine.assess([manual(symbol_spec=None,broker_loss_to_sl=None)],equity=10000)
        self.assertTrue(a.has_unbounded_risk)

    def test_trailing_stop_above_entry_still_counts_giveback_from_current_equity(self):
        a=self.engine.assess([
            manual(open_price=2000,current_price=2010,stop_loss=2005,volume=.5)
        ],equity=10000)
        self.assertAlmostEqual(a.open_risk_cash,250.0)

    def test_stop_beyond_current_market_has_zero_remaining_downside(self):
        a=self.engine.assess([
            manual(open_price=2000,current_price=2010,stop_loss=2011,volume=.5)
        ],equity=10000)
        self.assertAlmostEqual(a.open_risk_cash,0.0)

    def test_sell_risk(self):
        a=self.engine.assess([
            manual(side="SELL",open_price=2000,current_price=2000,stop_loss=2006,volume=.5)
        ],equity=10000)
        self.assertAlmostEqual(a.open_risk_cash,300.0)

    def test_invalid_equity_fails_closed(self):
        a=self.engine.assess([manual()],equity=0)
        self.assertTrue(a.has_unbounded_risk)

    def test_runtime_consumes_only_accepted_kat1_state(self):
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
            "position_identifier":77,
            "instrument_id":1,
            "spec_revision":1,
            "change_kind":1,
            "origin_class":3,
            "side":1,
            "volume_units":50,
            "open_price_units":200000,
            "current_price_units":200000,
            "sl_units":199400,
        }))
        a=rt.assessment()
        self.assertAlmostEqual(a.equity,10000.0)
        self.assertAlmostEqual(a.external_risk_fraction,.03)

        rejected=ValidationResult(
            EventEnvelope("position.state",{
                "position_identifier":77,
                "change_kind":2,
            }),
            ValidationDisposition.REJECT,
            (),
            2,
        )
        self.assertFalse(rt.observe(rejected))
        self.assertEqual(rt.assessment().position_count,1)

    def test_runtime_remove_closes_manual_risk(self):
        rt=Kat1SharedAccountRiskRuntime()
        rt.observe(accepted("account.state",{"equity_units":1000000,"account_currency_digits":2}))
        rt.observe(accepted("symbol.spec",{
            "instrument_id":1,"spec_revision":1,"price_scale":2,"volume_scale":2,
            "tick_size_units":1,"tick_value_loss_units":100,
        }))
        rt.observe(accepted("position.state",{
            "position_identifier":77,"instrument_id":1,"spec_revision":1,
            "change_kind":1,"origin_class":2,"side":1,"volume_units":50,
            "open_price_units":200000,"current_price_units":200000,"sl_units":199400,
        }))
        rt.observe(accepted("position.state",{"position_identifier":77,"change_kind":2}))
        self.assertEqual(rt.assessment().position_count,0)


if __name__=="__main__":
    unittest.main()
