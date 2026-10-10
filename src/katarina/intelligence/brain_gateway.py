"""Point-in-time snapshot adapter for offline KATARINA AI Brain research.

No broker API, networking, mutable risk authority or automated model promotion.
"""
from __future__ import annotations

from dataclasses import dataclass, replace
from datetime import datetime
from math import isfinite

from katarina.engines.decision import DecisionAction
from katarina.engines.opportunity import MarketCandidate
from katarina.engines.scalper_entry import EntryMode, ScalperEntryEngine, ScalperSnapshot
from katarina.engines.setup_quality import SetupQualityInput
from katarina.intelligence.brain import AIBrainSignal, AIBrainValidation, KatarinaAIBrain
from katarina.intelligence.market_universe import SymbolNewsExposureResolver, TradableInstrument
from katarina.intelligence.news_consensus import NewsConsensusEngine
from katarina.intelligence.news_intelligence import MultiSourceNewsEngine, NewsContext, NewsItem
from katarina.intelligence.regime import RegimeAssessment


FEATURE_NAMES = (
    "rsi14_norm", "adx14_norm", "atr_ratio", "mtf_alignment",
    "tick_velocity", "orderflow_imbalance", "spread_norm",
    "news_sentiment", "news_risk", "entry_score",
)


@dataclass(frozen=True, slots=True)
class BrainSnapshotInput:
    instrument: TradableInstrument
    scalper: ScalperSnapshot
    regime: RegimeAssessment
    news_items: tuple[NewsItem, ...]
    now_utc: datetime
    observed_ns: int
    liquidity_score: float
    correlation_penalty: float = 0.0
    system_healthy: bool = True


class AIBrainSnapshotGateway:
    """Combines the existing entry/news/quality modules into one research evaluation."""

    def __init__(self, brain: KatarinaAIBrain | None = None) -> None:
        self.brain = brain or KatarinaAIBrain()
        self.entry = ScalperEntryEngine()
        self.news = MultiSourceNewsEngine()
        self.consensus = NewsConsensusEngine()

    @staticmethod
    def features(snapshot: ScalperSnapshot, news: NewsContext, entry_score: float) -> tuple[float, ...]:
        if snapshot.atr_avg50 <= 0:
            raise ValueError("ATR reference missing")
        result = (
            snapshot.rsi14 / 100.0, snapshot.adx14 / 100.0,
            snapshot.atr14 / snapshot.atr_avg50,
            snapshot.mtf_alignment, snapshot.tick_velocity_norm,
            snapshot.orderflow_imbalance, snapshot.spread_bps / 10.0,
            news.sentiment, news.risk_score, entry_score,
        )
        if any(not isfinite(x) or abs(x) > 10 for x in result):
            raise ValueError("invalid or non-finite snapshot features")
        return result

    @staticmethod
    def _block(symbol: str, reason: str, *, unhealthy: bool = False) -> AIBrainSignal:
        return AIBrainSignal(
            symbol, DecisionAction.SAFE_MODE if unhealthy else DecisionAction.NO_TRADE,
            None, 0.0, 0.0, (reason,), "",
        )

    def evaluate(self, inp: BrainSnapshotInput, validation: AIBrainValidation) -> AIBrainSignal:
        symbol = inp.instrument.canonical_symbol
        if not inp.system_healthy:
            return self._block(symbol, "system_unhealthy", unhealthy=True)
        if not inp.instrument.ready or not inp.scalper.data_fresh:
            return self._block(symbol, "symbol_or_market_data_not_ready")
        if tuple(validation.feature_names) != FEATURE_NAMES:
            return self._block(symbol, "feature_schema_mismatch")
        if inp.now_utc.tzinfo is None:
            return self._block(symbol, "news_clock_unverified")
        if type(inp.observed_ns) is not int or inp.observed_ns <= 0:
            return self._block(symbol, "market_timestamp_invalid")
        news = self.news.assess(
            inp.news_items,
            exposures=SymbolNewsExposureResolver.exposures(inp.instrument),
            now_utc=inp.now_utc,
        )
        if not news.ready or news.blackout:
            return self._block(symbol, "news_context_unavailable_or_blackout")

        # Only already-published reports can affect the signed sentiment consensus.
        prior_items = tuple(x for x in inp.news_items if x.published_utc.tzinfo and x.published_utc <= inp.now_utc)
        consensus = self.consensus.assess(prior_items)
        if not consensus.ready:
            return self._block(symbol, "news_consensus_insufficient")
        snap = replace(inp.scalper, news_blackout=inp.scalper.news_blackout or news.blackout)
        proposal = self.entry.evaluate(inp.regime, snap)
        if not proposal.valid:
            return self._block(symbol, "entry_policy_rejected")
        limit = snap.spread_limit_bps
        if limit is None:
            limit = self.entry.config.momentum_max_spread_bps if proposal.mode is EntryMode.MOMENTUM_BREAKOUT else self.entry.config.max_spread_bps
        quality = SetupQualityInput(
            proposal, snap.mtf_alignment, snap.spread_bps, limit,
            inp.liquidity_score,
            snap.atr14 / snap.atr_avg50 if snap.atr_avg50 > 0 else 0.0,
            news.ready, news.blackout, news.risk_score,
            consensus.consensus, inp.correlation_penalty,
        )
        try:
            vector = self.features(snap, news, proposal.score)
        except ValueError:
            return self._block(symbol, "invalid_feature_vector")
        candidate = MarketCandidate(inp.instrument, proposal, news, snap.spread_bps, inp.liquidity_score, inp.correlation_penalty)
        return self.brain.evaluate(
            candidate, quality, validation,
            features=vector, observed_ns=inp.observed_ns,
            regime=inp.regime, system_healthy=inp.system_healthy,
        )
