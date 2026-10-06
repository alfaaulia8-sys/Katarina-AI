from __future__ import annotations
from dataclasses import dataclass
from hashlib import sha256

@dataclass(frozen=True, slots=True)
class Hypothesis:
    hypothesis_id: str
    question: str
    rationale: str
    metric: str
    production_mutation_allowed: bool=False

class ResearchEngine:
    def propose(self, question: str, rationale: str, metric: str) -> Hypothesis:
        if not question or not metric: raise ValueError("question/metric required")
        hid=sha256((question+"|"+rationale+"|"+metric).encode()).hexdigest()[:20]
        return Hypothesis(hid,question,rationale,metric,False)
