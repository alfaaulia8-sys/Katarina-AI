from __future__ import annotations
from dataclasses import dataclass
from math import isfinite

@dataclass(frozen=True, slots=True)
class LiveValidationEvidence:
    human_approved: bool
    demo_pass: bool
    broker_compatibility_pass: bool
    reconciliation_pass: bool
    stress_pass: bool
    monitoring_ready: bool
    requested_risk_fraction: float

@dataclass(frozen=True, slots=True)
class LiveValidationDecision:
    allowed: bool
    approved_risk_fraction: float
    reason: str

class LiveMicroRiskValidator:
    """Stage-38 live authorization gate.

    Risk parameters are intentionally identical across backtest, demo and real.
    The gate only controls whether real execution may start; it does not use a
    different risk profile.
    """
    HARD_RISK_CAP = 0.05
    HARD_MICRO_CAP = HARD_RISK_CAP  # compatibility alias for older callers

    def evaluate(self, e: LiveValidationEvidence) -> LiveValidationDecision:
        gates=(
            e.human_approved,
            e.demo_pass,
            e.broker_compatibility_pass,
            e.reconciliation_pass,
            e.stress_pass,
            e.monitoring_ready,
        )
        # A dataclass type annotation is not a runtime trust boundary:
        # the text "False", integers and other truthy placeholders must NOT
        # be accepted as signed approval / verified broker evidence.
        if any(type(flag) is not bool for flag in gates) or not all(gates):
            return LiveValidationDecision(False,0.0,"validation_gate_incomplete")
        requested=e.requested_risk_fraction
        if (type(requested) not in (float,int)):
            return LiveValidationDecision(False,0.0,"invalid_risk")
        try:
            finite=isfinite(requested)
        except (OverflowError,ValueError,TypeError):
            finite=False
        if not finite or requested<=0:
            return LiveValidationDecision(False,0.0,"invalid_risk")
        return LiveValidationDecision(
            True,
            min(float(requested),self.HARD_RISK_CAP),
            "unified_risk_profile",
        )
