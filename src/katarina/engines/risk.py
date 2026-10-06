from __future__ import annotations
from dataclasses import dataclass
from enum import Enum
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from katarina.engines.manual_risk import AccountRiskAssessment

class RiskAction(str, Enum):
    APPROVE="APPROVE"; REDUCE="REDUCE"; REJECT="REJECT"; PAUSE="PAUSE"

@dataclass(frozen=True, slots=True)
class RiskRequest:
    requested_fraction: float
    open_risk_fraction: float
    drawdown_fraction: float
    uncertainty: float
    expected_rr: float
    health_ok: bool
    reconciled: bool
    daily_drawdown_fraction: float = 0.0
    unbounded_open_risk: bool = False

@dataclass(frozen=True, slots=True)
class RiskDecision:
    action: RiskAction
    approved_fraction: float
    reason: str

class RiskGovernor:
    def __init__(
        self,
        *,
        per_trade_default: float = 0.01,
        hard_per_trade: float = 0.05,
        max_open_risk: float = 0.08,
        max_drawdown: float = 0.20,
        max_daily_drawdown: float = 0.10,
    ):
        self.per_trade_default=per_trade_default
        self.hard_per_trade=hard_per_trade
        self.max_open_risk=max_open_risk
        self.max_drawdown=max_drawdown
        self.max_daily_drawdown=max_daily_drawdown

    def evaluate(self, r: RiskRequest) -> RiskDecision:
        if not r.health_ok or not r.reconciled:
            return RiskDecision(RiskAction.PAUSE,0.0,"health_or_reconciliation")
        if r.unbounded_open_risk:
            return RiskDecision(RiskAction.PAUSE,0.0,"unbounded_open_risk")
        if r.daily_drawdown_fraction >= self.max_daily_drawdown:
            return RiskDecision(RiskAction.PAUSE,0.0,"daily_drawdown_limit")
        if r.drawdown_fraction >= self.max_drawdown:
            return RiskDecision(RiskAction.REJECT,0.0,"drawdown_limit")
        if r.expected_rr <= 0 or r.uncertainty >= 0.75:
            return RiskDecision(RiskAction.REJECT,0.0,"insufficient_edge")

        remaining=max(0.0,self.max_open_risk-r.open_risk_fraction)
        cap=min(self.hard_per_trade,remaining)
        approved=min(max(0.0,r.requested_fraction),cap)
        if approved <= 0:
            return RiskDecision(RiskAction.REJECT,0.0,"risk_capacity_exhausted")
        if approved < r.requested_fraction:
            return RiskDecision(RiskAction.REDUCE,approved,"hard_risk_cap")
        return RiskDecision(RiskAction.APPROVE,approved,"within_limits")

    def evaluate_state(
        self,
        state,
        *,
        requested_fraction: float,
        uncertainty: float,
        expected_rr: float,
        health_ok: bool,
        reconciled: bool,
    ) -> RiskDecision:
        """Evaluate a full AccountRiskStateSnapshot including pending/reserved risk."""
        return self.evaluate(
            RiskRequest(
                requested_fraction=requested_fraction,
                open_risk_fraction=state.total_committed_risk_fraction,
                drawdown_fraction=state.total_drawdown_fraction,
                uncertainty=uncertainty,
                expected_rr=expected_rr,
                health_ok=health_ok,
                reconciled=reconciled,
                daily_drawdown_fraction=state.daily_drawdown_fraction,
                unbounded_open_risk=state.has_unbounded_risk,
            )
        )

    def evaluate_account(
        self,
        account_risk: "AccountRiskAssessment",
        *,
        requested_fraction: float,
        drawdown_fraction: float,
        daily_drawdown_fraction: float,
        uncertainty: float,
        expected_rr: float,
        health_ok: bool,
        reconciled: bool,
    ) -> RiskDecision:
        """Mandatory shared-account path for new KATARINA exposure."""
        return self.evaluate(
            RiskRequest(
                requested_fraction=requested_fraction,
                open_risk_fraction=account_risk.open_risk_fraction,
                drawdown_fraction=drawdown_fraction,
                uncertainty=uncertainty,
                expected_rr=expected_rr,
                health_ok=health_ok,
                reconciled=reconciled,
                daily_drawdown_fraction=daily_drawdown_fraction,
                unbounded_open_risk=account_risk.has_unbounded_risk,
            )
        )
