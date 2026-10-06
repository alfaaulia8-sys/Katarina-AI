from __future__ import annotations
from dataclasses import dataclass
from typing import Mapping

@dataclass(frozen=True, slots=True)
class CiAssessment:
    passed: bool
    missing: tuple[str,...]
    failing: tuple[str,...]

class AutomatedTestingPolicy:
    REQUIRED=("unit","static","compile","audit")
    def assess(self, results: Mapping[str,bool]) -> CiAssessment:
        missing=tuple(x for x in self.REQUIRED if x not in results)
        failing=tuple(x for x in self.REQUIRED if x in results and not results[x])
        return CiAssessment(not missing and not failing,missing,failing)
