from __future__ import annotations

from dataclasses import replace
from datetime import datetime, timedelta, timezone
import unittest

from katarina.engines.decision import DecisionAction
from katarina.engines.scalper_entry import ScalperSnapshot
from katarina.intelligence.brain import KatarinaAIBrain, LabeledMarketExample
from katarina.intelligence.brain_gateway import AIBrainSnapshotGateway, BrainSnapshotInput, FEATURE_NAMES
from katarina.intelligence.market_universe import TradableInstrument, AssetClass
from katarina.intelligence.news_intelligence import NewsItem
from katarina.intelligence.regime import Regime, RegimeAssessment


def base_input():
    now = datetime(2026, 10, 10, tzinfo=timezone.utc)
    instrument = TradableInstrument(
        11, 1, "EURUSD", "EURUSD", "EUR", "USD", "USD", AssetClass.FOREX,
        True, True, True, True, True, True,
    )
    snapshot = ScalperSnapshot(
        open=1999.8, high=2003.0, low=1999.5, close=2001.0,
        ema10=2000.0, ema50=1995.0, ema50_prev=1994.0,
        rsi14=55, rsi2=50, bb_lower=1988, bb_mid=2000, bb_upper=2012,
        atr14=5, atr_avg50=5, adx14=30, reference_high=2005,
        reference_low=1995, vwap=1999, tick_velocity_norm=.6,
        orderflow_imbalance=.3, mtf_alignment=.8, htf_direction=1,
        spread_bps=.5, session="LONDON",
    )
    news = (NewsItem("fed", now - timedelta(minutes=60), "USD macro research",
                     ("USD",), 1, .5),)
    return BrainSnapshotInput(instrument, snapshot, RegimeAssessment(Regime.TREND_UP, .8, False),
                              news, now, 100_000, .95)


class GatewayTests(unittest.TestCase):
    def setUp(self):
        self.gateway = AIBrainSnapshotGateway()
        self.inp = base_input()
        initial_news = self.gateway.news.assess(
            self.inp.news_items, exposures=("EUR", "USD", "FX"),
            now_utc=self.inp.now_utc,
        )
        from katarina.engines.scalper_entry import ScalperEntryEngine
        proposal = ScalperEntryEngine().evaluate(self.inp.regime, self.inp.scalper)
        vector = self.gateway.features(self.inp.scalper, initial_news, proposal.score)
        rows = [
            LabeledMarketExample(
                f"synthetic-{i}", (i+1)*1000, (i+1)*1000+200,
                vector if i % 2 else tuple(-x for x in vector), i % 2,
            ) for i in range(70)
        ]
        self.report = KatarinaAIBrain().train_candidate(rows, feature_names=FEATURE_NAMES)

    def test_snapshot_to_ai_candidate_is_research_only(self):
        self.assertTrue(self.report.valid, self.report.reasons)
        signal = self.gateway.evaluate(self.inp, self.report)
        self.assertEqual(signal.action, DecisionAction.BUY, signal.reasons)
        self.assertTrue(signal.research_only)
        self.assertFalse(signal.live_risk_authorized)
        self.assertGreater(signal.net_win_probability, .55)

    def test_broker_data_health_and_news_veto(self):
        disabled = replace(self.inp.instrument, session_open=False)
        self.assertEqual(self.gateway.evaluate(replace(self.inp, instrument=disabled), self.report).action, DecisionAction.NO_TRADE)
        self.assertEqual(self.gateway.evaluate(replace(self.inp, system_healthy=False), self.report).action, DecisionAction.SAFE_MODE)
        self.assertEqual(self.gateway.evaluate(replace(self.inp, news_items=()), self.report).action, DecisionAction.NO_TRADE)
        item = NewsItem("fed", self.inp.now_utc, "USD rate decision", ("USD",), 3, .8)
        self.assertEqual(self.gateway.evaluate(replace(self.inp, news_items=(item,)), self.report).action, DecisionAction.NO_TRADE)

    def test_no_future_news_affects_consensus(self):
        future = NewsItem("reuters", self.inp.now_utc + timedelta(minutes=90),
                          "Future report", ("USD",), 1, -.5)
        out = self.gateway.evaluate(replace(self.inp, news_items=self.inp.news_items + (future,)), self.report)
        self.assertEqual(out.action, DecisionAction.BUY, out.reasons)

    def test_research_schema_rejects_wrong_feature_order(self):
        mismatched = replace(self.report, feature_names=tuple(reversed(FEATURE_NAMES)))
        signal = self.gateway.evaluate(self.inp, mismatched)
        self.assertEqual(signal.action, DecisionAction.NO_TRADE)
        self.assertIn("feature_schema_mismatch", signal.reasons)

    def test_naive_clock_fails_closed(self):
        naive = self.inp.now_utc.replace(tzinfo=None)
        signal = self.gateway.evaluate(replace(self.inp, now_utc=naive), self.report)
        self.assertIn("news_clock_unverified", signal.reasons)


if __name__ == "__main__":
    unittest.main()
