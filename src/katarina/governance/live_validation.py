from __future__ import annotations
from dataclasses import dataclass

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
        if not all(gates):
            return LiveValidationDecision(False,0.0,"validation_gate_incomplete")
        if e.requested_risk_fraction<=0:
            return LiveValidationDecision(False,0.0,"invalid_risk")
        return LiveValidationDecision(
            True,
            min(e.requested_risk_fraction,self.HARD_RISK_CAP),
            "unified_risk_profile",
        )
