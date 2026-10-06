from __future__ import annotations
from dataclasses import dataclass

@dataclass(frozen=True, slots=True)
class ShadowComparison:
    production_action: str
    candidate_action: str
    agreement: bool
    production_score: float
    candidate_score: float
    broker_mutation_allowed: bool=False

class ShadowKatarina:
    def compare(self, production_action: str, candidate_action: str, production_score: float, candidate_score: float) -> ShadowComparison:
        return ShadowComparison(production_action,candidate_action,production_action==candidate_action,production_score,candidate_score,False)
