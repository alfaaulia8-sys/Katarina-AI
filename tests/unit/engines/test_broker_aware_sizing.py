"""Synthetic-only Stage 16/17 risk, broker cost and margin regression."""
from dataclasses import replace
from pathlib import Path
import unittest

from katarina.engines.broker_aware_sizing import (
    AccountFacts, BrokerFacts, TradingCosts, ResearchCostMarginGate)
from katarina.engines.risk import RiskGovernor

CONFIG = Path(__file__).resolve().parents[3]/"config"/"risk_governor_v2.json"


class ResearchCostMarginGateTests(unittest.TestCase):
    def setUp(self):
        self.gate = ResearchCostMarginGate(RiskGovernor.from_config(CONFIG))
        self.account = AccountFacts("USD",1000,1000,1000,1000,verified=True)
        self.broker = BrokerFacts("USD",1,100,.01,50,.01,1000,verified=True)
        self.costs = TradingCosts(.02,.03,.5,verified=True)

    def qualify(self, **changes):
        inputs=dict(account=self.account,broker=self.broker,costs=self.costs,
                    side="BUY",entry=4200,stop=4190)
        inputs.update(changes)
        return self.gate.qualify(**inputs)

    def test_three_capitals_reject_too_large_minimum_lot(self):
        eligible=[]
        for capital in (100,1000,10000):
            a=replace(self.account,active_capital=capital,equity=capital,
                      peak_reference_capital=capital,available_margin=capital)
            out=self.qualify(account=a)
            self.assertFalse(out.live_execution_authorized)
            eligible.append(out)
        self.assertFalse(eligible[0].eligible_for_research)
        self.assertEqual(eligible[0].reason,"min_lot_exceeds_risk_or_margin")
        for result in eligible[1:]:
            self.assertTrue(result.eligible_for_research)
            self.assertLessEqual(result.buffered_loss_native,result.budget_native+1e-8)
        self.assertGreater(eligible[1].fraction,eligible[2].fraction)

    def test_missing_verification_blocks(self):
        self.assertEqual(self.qualify(account=replace(self.account,verified=False)).reason,
                         "unverified_account_contract_or_cost")
        self.assertFalse(self.qualify(broker=replace(self.broker,verified=False)).eligible_for_research)
        self.assertFalse(self.qualify(costs=replace(self.costs,verified=False)).eligible_for_research)

    def test_buy_and_sell_stops(self):
        self.assertFalse(self.qualify(stop=4210).eligible_for_research)
        self.assertFalse(self.qualify(side="SELL",stop=4190).eligible_for_research)
        self.assertTrue(self.qualify(side="SELL",stop=4210).eligible_for_research)

    def test_cost_margin_stress(self):
        a=self.qualify()
        b=self.qualify(costs=replace(self.costs,spread_distance=2,adverse_slippage_distance=3,
                                    round_trip_fee_per_lot=15))
        self.assertTrue(a.eligible_for_research)
        self.assertLessEqual(b.volume,a.volume)
        self.assertFalse(self.qualify(account=replace(self.account,available_margin=5)).eligible_for_research)

    def test_drawdown_unbounded_and_open_risk(self):
        self.assertIn("governor_",self.qualify(
            account=replace(self.account,daily_drawdown=.10)).reason)
        self.assertIn("governor_",self.qualify(
            account=replace(self.account,unbounded_risk=True)).reason)
        self.assertFalse(self.qualify(account=replace(self.account,committed_risk_fraction=.079)).eligible_for_research)

    def test_currency_bad_contract_and_nonfinite(self):
        self.assertFalse(self.qualify(account=replace(self.account,native_currency="JPY")).eligible_for_research)
        self.assertFalse(self.qualify(broker=replace(self.broker,contract_revision=0)).eligible_for_research)
        self.assertFalse(self.qualify(broker=replace(self.broker,volume_step=0)).eligible_for_research)
        self.assertFalse(self.qualify(account=replace(self.account,equity=float("nan"))).eligible_for_research)

    def test_cent_proxy_not_live_authorization(self):
        a=AccountFacts("USC",10000,10000,10000,10000,verified=True)
        b=BrokerFacts("USC",1,100,.01,50,.01,200,verified=True)
        r=self.qualify(account=a,broker=b)
        self.assertTrue(r.eligible_for_research)
        self.assertAlmostEqual(r.fraction,.02)
        self.assertFalse(r.live_execution_authorized)

    def test_risk_soft_limit_reduces_lots(self):
        normal=self.qualify()
        softer=self.qualify(account=replace(self.account,daily_drawdown=.051))
        self.assertTrue(normal.eligible_for_research)
        self.assertLess(softer.fraction,normal.fraction)
        self.assertLessEqual(softer.volume,normal.volume)


if __name__=="__main__":
    unittest.main()
