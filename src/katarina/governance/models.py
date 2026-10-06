from __future__ import annotations
from dataclasses import dataclass
from enum import Enum

class ModelState(str, Enum):
    CANDIDATE="CANDIDATE"; SHADOW="SHADOW"; ACTIVE="ACTIVE"; RETIRED="RETIRED"; ROLLED_BACK="ROLLED_BACK"

@dataclass(frozen=True, slots=True)
class PromotionEvidence:
    oos_pass: bool
    walkforward_pass: bool
    robustness_pass: bool
    shadow_pass: bool
    simpler_not_worse: bool
@dataclass(frozen=True, slots=True)
class PromotionDecision:
    allowed: bool
    target_state: ModelState
    reason: str

class ModelPromotionController:
    def evaluate(self, evidence: PromotionEvidence) -> PromotionDecision:
        ok=all((evidence.oos_pass,evidence.walkforward_pass,evidence.robustness_pass,evidence.shadow_pass,evidence.simpler_not_worse))
        return PromotionDecision(ok,ModelState.ACTIVE if ok else ModelState.CANDIDATE,"all_gates_pass" if ok else "validation_incomplete")
    def rollback(self, reason: str) -> PromotionDecision:
        return PromotionDecision(True,ModelState.ROLLED_BACK,reason or "degradation")
