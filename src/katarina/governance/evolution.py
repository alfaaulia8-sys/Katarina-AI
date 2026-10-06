from __future__ import annotations
from dataclasses import dataclass

@dataclass(frozen=True, slots=True)
class EvolutionProposal:
    proposal_id: str
    hypothesis_id: str
    candidate_version: str
    validation_pass: bool
    shadow_pass: bool
    constitution_change: bool=False
@dataclass(frozen=True, slots=True)
class EvolutionDecision:
    action: str
    reason: str

class ContinuousEvolutionController:
    def decide(self, p: EvolutionProposal) -> EvolutionDecision:
        if p.constitution_change: return EvolutionDecision("REJECT","constitution_is_frozen")
        if not p.validation_pass: return EvolutionDecision("RESEARCH","validation_required")
        if not p.shadow_pass: return EvolutionDecision("SHADOW","shadow_required")
        return EvolutionDecision("PROMOTION_REVIEW","human_governed_promotion_required")
    def autonomous_live_promotion_allowed(self) -> bool:
        return False
