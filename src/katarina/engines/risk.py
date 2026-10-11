from __future__ import annotations
from dataclasses import dataclass
from enum import Enum
from math import isfinite
from pathlib import Path
from typing import TYPE_CHECKING
import json

from katarina.engines.adaptive_risk import AdaptiveRiskProfile

if TYPE_CHECKING:
    from katarina.engines.manual_risk import AccountRiskAssessment

class RiskAction(str, Enum):
    APPROVE="APPROVE"; REDUCE="REDUCE"; REJECT="REJECT"; PAUSE="PAUSE"

@dataclass(frozen=True, slots=True)
class RiskRequest:
    requested_fraction: float | None
    open_risk_fraction: float
    drawdown_fraction: float
    uncertainty: float
    expected_rr: float
    health_ok: bool
    reconciled: bool
    daily_drawdown_fraction: float = 0.0
    unbounded_open_risk: bool = False
    # Required only when an adaptive profile is enabled; native broker units.
    risk_capital: float | None = None
    risk_reference_capital: float | None = None
    account_currency: str | None = None

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
        adaptive_profile: AdaptiveRiskProfile | None = None,
    ):
        vals=(per_trade_default,hard_per_trade,max_open_risk,max_drawdown,max_daily_drawdown)
        if any(not isfinite(v) or v<=0 for v in vals):
            raise ValueError("invalid_risk_limits")
        if (per_trade_default>.05 or hard_per_trade>.05 or
                max_open_risk>.08 or max_daily_drawdown>.10 or
                max_drawdown>.20):
            raise ValueError("cannot_expand_fixed_safety_limits")
        self.per_trade_default=per_trade_default
        self.hard_per_trade=hard_per_trade
        self.max_open_risk=max_open_risk
        self.max_drawdown=max_drawdown
        self.max_daily_drawdown=max_daily_drawdown
        self.adaptive_profile=adaptive_profile

    @classmethod
    def from_config(cls, path: str | Path) -> "RiskGovernor":
        """Opt-in creation from a verified risk config; not live authorization."""
        obj=json.loads(Path(path).read_text(encoding="utf-8"))
        options=obj.get("adaptive_risk",{})
        adaptive=None
        if options.get("enabled",False):
            tiers=options.get("tiers_usd")
            scales=options.get("money_units_per_usd")
            if not isinstance(tiers,list) or not isinstance(scales,dict):
                raise ValueError("adaptive_config_missing_tiers_or_currency")
            adaptive=AdaptiveRiskProfile(
                tiers_usd=tuple((float(x[0]),float(x[1])) for x in tiers),
                money_units_per_usd=scales,
                soft_daily_drawdown=float(options["soft_daily_drawdown"]),
                soft_total_drawdown=float(options["soft_total_drawdown"]),
                drawdown_multiplier=float(options["drawdown_multiplier"]),
            )
        return cls(
            per_trade_default=float(obj["per_trade_default_fraction"]),
            hard_per_trade=float(obj["hard_per_entry_fraction"]),
            max_open_risk=float(obj["max_open_risk_fraction"]),
            max_drawdown=float(obj["max_total_drawdown_fraction"]),
            max_daily_drawdown=float(obj["max_daily_drawdown_fraction"]),
            adaptive_profile=adaptive,
        )

    def evaluate(self, r: RiskRequest) -> RiskDecision:
        if not r.health_ok or not r.reconciled:
            return RiskDecision(RiskAction.PAUSE,0.0,"health_or_reconciliation")
        if r.unbounded_open_risk:
            return RiskDecision(RiskAction.PAUSE,0.0,"unbounded_open_risk")
        values=(r.open_risk_fraction,r.drawdown_fraction,r.daily_drawdown_fraction,
                r.uncertainty,r.expected_rr)
        if any(not isfinite(v) for v in values):
            return RiskDecision(RiskAction.PAUSE,0.0,"invalid_risk_evidence")
        if r.open_risk_fraction<0 or r.drawdown_fraction<0 or r.daily_drawdown_fraction<0:
            return RiskDecision(RiskAction.PAUSE,0.0,"invalid_risk_evidence")
        if r.daily_drawdown_fraction >= self.max_daily_drawdown:
            return RiskDecision(RiskAction.PAUSE,0.0,"daily_drawdown_limit")
        if r.drawdown_fraction >= self.max_drawdown:
            return RiskDecision(RiskAction.REJECT,0.0,"drawdown_limit")
        if r.expected_rr <= 0 or r.uncertainty >= 0.75:
            return RiskDecision(RiskAction.REJECT,0.0,"insufficient_edge")

        remaining=max(0.0,self.max_open_risk-r.open_risk_fraction)
        cap=min(self.hard_per_trade,remaining)
        cap_without_adaptive=cap
        adaptive=None
        if self.adaptive_profile is not None:
            try:
                adaptive=self.adaptive_profile.quote(
                    active_capital_native=r.risk_capital,
                    reference_capital_native=r.risk_reference_capital,
                    account_currency=r.account_currency,
                    daily_drawdown=r.daily_drawdown_fraction,
                    total_drawdown=r.drawdown_fraction,
                )
            except (TypeError,ValueError,OverflowError):
                return RiskDecision(RiskAction.PAUSE,0.0,"adaptive_capital_unverified")
            cap=min(cap,adaptive.fraction)
        requested=self.per_trade_default if r.requested_fraction is None else r.requested_fraction
        if adaptive is not None and r.requested_fraction is None:
            requested=adaptive.fraction
        if not isfinite(requested) or requested<0:
            return RiskDecision(RiskAction.REJECT,0.0,"invalid_requested_risk")
        approved=min(requested,cap)
        if approved<=0:
            return RiskDecision(RiskAction.REJECT,0.0,"risk_capacity_exhausted")
        if approved<requested-1e-12:
            reason=("adaptive_capital_risk_cap"
                    if adaptive is not None and adaptive.fraction<cap_without_adaptive-1e-12
                    else "hard_risk_cap")
            return RiskDecision(RiskAction.REDUCE,approved,reason)
        return RiskDecision(RiskAction.APPROVE,approved,
            adaptive.reason if adaptive is not None else "within_limits")

    def evaluate_state(
        self,
        state,
        *,
        requested_fraction: float | None,
        uncertainty: float,
        expected_rr: float,
        health_ok: bool,
        reconciled: bool,
        account_currency: str | None = None,
        risk_reference_capital: float | None = None,
    ) -> RiskDecision:
        """Evaluate a full account snapshot; includes pending/reserved/manual risk."""
        return self.evaluate(RiskRequest(
            requested_fraction=requested_fraction,
            open_risk_fraction=state.total_committed_risk_fraction,
            drawdown_fraction=state.total_drawdown_fraction,
            uncertainty=uncertainty,
            expected_rr=expected_rr,
            health_ok=health_ok,
            reconciled=reconciled,
            daily_drawdown_fraction=state.daily_drawdown_fraction,
            unbounded_open_risk=state.has_unbounded_risk,
            risk_capital=state.risk_capital,
            risk_reference_capital=risk_reference_capital,
            account_currency=account_currency,
        ))

    def evaluate_account(
        self,
        account_risk: "AccountRiskAssessment",
        *,
        requested_fraction: float | None,
        drawdown_fraction: float,
        daily_drawdown_fraction: float,
        uncertainty: float,
        expected_rr: float,
        health_ok: bool,
        reconciled: bool,
        risk_capital: float | None = None,
        risk_reference_capital: float | None = None,
        account_currency: str | None = None,
    ) -> RiskDecision:
        """Shared-account path; adaptive mode requires verified capital & currency."""
        return self.evaluate(RiskRequest(
            requested_fraction=requested_fraction,
            open_risk_fraction=account_risk.open_risk_fraction,
            drawdown_fraction=drawdown_fraction,
            uncertainty=uncertainty,
            expected_rr=expected_rr,
            health_ok=health_ok,
            reconciled=reconciled,
            daily_drawdown_fraction=daily_drawdown_fraction,
            unbounded_open_risk=account_risk.has_unbounded_risk,
            risk_capital=risk_capital,
            risk_reference_capital=risk_reference_capital,
            account_currency=account_currency,
        ))
