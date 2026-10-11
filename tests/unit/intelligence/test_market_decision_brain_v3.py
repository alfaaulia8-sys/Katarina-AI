"""Autonomous decision cards are conditional research advice, never broker orders."""
import unittest
from dataclasses import replace
from datetime import timedelta
from katarina.intelligence.market_decision_brain_v3 import MarketDecisionBrain
from tests.unit.intelligence.test_market_decision_pipeline import NOW, market

class TestMarketDecisionBrainV3(unittest.TestCase):
    def setUp(self):
        self.brain=MarketDecisionBrain()
        self.params=dict(symbol="XAUUSD.vx",candles=market("up"),as_of_utc=NOW,
                         actual_spread=.02,broker_session_open=True,
                         data_fresh=True,news_blackout=False)
    def test_all_six_questions_are_answered(self):
        out=self.brain.evaluate(**self.params)
        self.assertIn(out.market_state,("TREND_UP","PULLBACK_UP"))
        self.assertIn("BULLISH",out.directional_bias)
        self.assertIn("Jika",out.primary_scenario)
        self.assertIn("Jika",out.alternative_scenario)
        self.assertEqual(out.strategy,"TREND_PULLBACK")
        self.assertIn(out.technical_signal,("BUY","WAIT"))
        self.assertEqual(out.decision,"WAIT")
        self.assertGreater(out.evidence_score,0)
        self.assertTrue(out.next_trigger)
        self.assertTrue(out.evidence_not_probability)
        self.assertFalse(out.live_execution_authorized)
    def test_news_unverified_does_not_block_market_read(self):
        x=self.brain.evaluate(**self.params)
        self.assertNotEqual(x.market_state,"UNKNOWN")
        self.assertEqual(x.decision,"WAIT")
        self.assertIn("news_context_unverified",x.blockers)
    def test_strategy_not_validated_stays_wait_even_if_risk_ok(self):
        x=self.brain.evaluate(**self.params,news_context_verified=True,risk_approved_for_paper=True)
        self.assertIn("pair_strategy_edge_not_validated",x.blockers)
        self.assertEqual(x.decision,"WAIT")
    def test_scenario_invalidation_opposite_to_bias(self):
        for trend,expected in (("up",True),("down",False)):
            x=self.brain.evaluate(**{**self.params,"candles":market(trend)})
            price=market(trend)["M5"][-1].close
            self.assertEqual(x.invalidation_level<price,expected)
            self.assertTrue(x.primary_target>price if expected else x.primary_target<price)
    def test_closed_session_always_wait(self):
        x=self.brain.evaluate(**{**self.params,"broker_session_open":False},news_context_verified=True)
        self.assertIn("market_closed_or_data_stale",x.blockers)
        self.assertEqual(x.decision,"WAIT")
    def test_news_blackout_always_wait(self):
        x=self.brain.evaluate(**{**self.params,"news_blackout":True},news_context_verified=True)
        self.assertIn("high_impact_news_blackout",x.blockers)
    def test_spread_block(self):
        x=self.brain.evaluate(**{**self.params,"actual_spread":.4},news_context_verified=True)
        self.assertIn("spread_too_high_for_volatility",x.blockers)
        self.assertEqual(x.decision,"WAIT")
    def test_stale_or_future_data_fails_closed(self):
        x=self.brain.evaluate(**{**self.params,"as_of_utc":NOW+timedelta(hours=2)})
        self.assertEqual(x.decision,"WAIT")
        self.assertEqual(x.market_state,"UNKNOWN")
        bars=market()
        bars["M5"][-1]=replace(bars["M5"][-1],closed_at_utc=NOW+timedelta(minutes=10))
        x=self.brain.evaluate(**{**self.params,"candles":bars})
        self.assertEqual(x.market_state,"UNKNOWN")
    def test_synthetic_paper_approval_still_never_enables_live(self):
        b=MarketDecisionBrain(minimum_evidence_score=.4,minimum_rr=.0001)
        evidence={("XAUUSD.vx","TREND_PULLBACK","BUY"):True}
        x=b.evaluate(**self.params,news_context_verified=True,
                     strategy_evidence=evidence,risk_approved_for_paper=True)
        self.assertEqual(x.technical_signal,"BUY")
        self.assertEqual(x.decision,"BUY")
        self.assertFalse(x.live_execution_authorized)
        self.assertTrue(x.research_only)
    def test_wrong_pair_edge_does_not_leak(self):
        b=MarketDecisionBrain(minimum_evidence_score=.4,minimum_rr=.0001)
        x=b.evaluate(**self.params,news_context_verified=True,
                     strategy_evidence={("EURUSD.vx","TREND_PULLBACK","BUY"):True},
                     risk_approved_for_paper=True)
        self.assertFalse(x.strategy_validated)
        self.assertEqual(x.decision,"WAIT")
    def test_missing_or_invalid_history(self):
        x=self.brain.evaluate(**{**self.params,"candles":{"M5":[]}})
        self.assertEqual(x.market_state,"UNKNOWN")
        self.assertIn("insufficient_closed_market_history",x.blockers)
    def test_pipeline_keeps_separate_potential_setup(self):
        raw=self.brain.observer.evaluate(**{k:v for k,v in self.params.items()},
                                         news_context_verified=False)
        self.assertEqual(raw.action,"WAIT")
        self.assertEqual(raw.potential_action,"BUY")
        self.assertTrue(raw.setup_ready)

if __name__=="__main__":unittest.main()