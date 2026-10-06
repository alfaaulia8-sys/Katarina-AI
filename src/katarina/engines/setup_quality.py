from __future__ import annotations

from dataclasses import dataclass
from math import isfinite

from katarina.engines.scalper_entry import EntryProposal


@dataclass(frozen=True, slots=True)
class SetupQualityInput:
    proposal: EntryProposal
    mtf_alignment: float
    spread_bps: float
    spread_limit_bps: float
    liquidity_score: float
    atr_ratio: float
    news_ready: bool
    news_blackout: bool
    news_risk_score: float
    source_consensus: float
    correlation_penalty: float = 0.0


@dataclass(frozen=True, slots=True)
class SetupQualityResult:
    valid: bool
    adjusted_score: float
    risk_multiplier: float
    reasons: tuple[str,...]


class SetupQualityEngine:
    """Cross-market quality gate.

    This layer never increases requested risk. It can only keep or reduce it.
    Thresholds are engineering defaults and must be calibrated by KATARINA's
    own real-tick / walk-forward evidence.
    """

    def __init__(
        self,
        *,
        min_adjusted_score: float=.62,
        min_liquidity: float=.35,
        min_atr_ratio: float=.45,
        max_atr_ratio: float=2.75,
    ):
        self.min_adjusted_score=min_adjusted_score
        self.min_liquidity=min_liquidity
        self.min_atr_ratio=min_atr_ratio
        self.max_atr_ratio=max_atr_ratio

    @staticmethod
    def _clip(v:float)->float:
        return max(0.0,min(1.0,float(v)))

    def evaluate(self,x:SetupQualityInput)->SetupQualityResult:
        values=(x.mtf_alignment,x.spread_bps,x.spread_limit_bps,x.liquidity_score,
                x.atr_ratio,x.news_risk_score,x.source_consensus,x.correlation_penalty)
        if any(not isfinite(v) for v in values):
            return SetupQualityResult(False,0.0,0.0,("non_finite_quality_input",))
        if not x.proposal.valid:
            return SetupQualityResult(False,0.0,0.0,("entry_proposal_invalid",))
        if not x.news_ready:
            return SetupQualityResult(False,0.0,0.0,("news_context_unavailable",))
        if x.news_blackout:
            return SetupQualityResult(False,0.0,0.0,("news_blackout",))
        if x.spread_limit_bps<=0 or x.spread_bps<0 or x.spread_bps>x.spread_limit_bps:
            return SetupQualityResult(False,0.0,0.0,("spread_efficiency_failed",))
        if x.liquidity_score<self.min_liquidity:
            return SetupQualityResult(False,0.0,0.0,("liquidity_too_low",))
        if x.atr_ratio<self.min_atr_ratio:
            return SetupQualityResult(False,0.0,0.0,("volatility_too_low",))
        if x.atr_ratio>self.max_atr_ratio:
            return SetupQualityResult(False,0.0,0.0,("volatility_extreme",))

        spread_quality=self._clip(1.0-x.spread_bps/x.spread_limit_bps)
        if .75<=x.atr_ratio<=1.75:
            vol_quality=1.0
        elif x.atr_ratio<.75:
            vol_quality=self._clip((x.atr_ratio-self.min_atr_ratio)/(.75-self.min_atr_ratio))
        else:
            vol_quality=self._clip((self.max_atr_ratio-x.atr_ratio)/(self.max_atr_ratio-1.75))

        news_clarity=self._clip(x.source_consensus)*(1.0-.65*self._clip(x.news_risk_score))
        correlation_quality=1.0-self._clip(x.correlation_penalty/.50)
        score=(
            .42*self._clip(x.proposal.score)
            +.16*self._clip(x.mtf_alignment)
            +.12*self._clip(x.liquidity_score)
            +.10*spread_quality
            +.08*vol_quality
            +.07*news_clarity
            +.05*correlation_quality
        )
        score=self._clip(score)
        if score<self.min_adjusted_score:
            return SetupQualityResult(False,score,0.0,("quality_score_below_threshold",))

        # Conditional risk discount: never >1.0 and never increases requested risk.
        if score>=.82:
            multiplier=1.0
        elif score>=.72:
            multiplier=.75
        else:
            multiplier=.50
        if x.atr_ratio>2.0:
            multiplier=min(multiplier,.50)
        elif x.atr_ratio>1.75:
            multiplier=min(multiplier,.75)
        if x.news_risk_score>.65:
            multiplier=min(multiplier,.50)

        return SetupQualityResult(
            True,score,multiplier,
            ("entry_edge","mtf_confirmation","cost_efficiency","liquidity",
             "conditional_volatility","news_consensus","portfolio_context")
        )
