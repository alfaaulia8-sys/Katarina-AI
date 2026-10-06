from __future__ import annotations
from dataclasses import dataclass
from math import sqrt
from typing import Mapping,Sequence

def pearson(a: Sequence[float], b: Sequence[float]) -> float:
    if len(a)!=len(b) or len(a)<2: return 0.0
    ma=sum(a)/len(a); mb=sum(b)/len(b)
    xa=[x-ma for x in a]; xb=[x-mb for x in b]
    den=sqrt(sum(x*x for x in xa)*sum(x*x for x in xb))
    return 0.0 if den==0 else max(-1.0,min(1.0,sum(x*y for x,y in zip(xa,xb))/den))

@dataclass(frozen=True, slots=True)
class ExposureAssessment:
    gross_risk: float
    correlation_penalty: float
    adjusted_risk: float
    allowed: bool

class CorrelationExposureEngine:
    def assess(self, risks: Mapping[str,float], returns: Mapping[str,Sequence[float]], *, cap: float=0.08) -> ExposureAssessment:
        gross=sum(max(0.0,float(v)) for v in risks.values())
        syms=sorted(risks); penalty=0.0
        for i,a in enumerate(syms):
            for b in syms[i+1:]:
                corr=max(0.0,pearson(returns.get(a,()),returns.get(b,())))
                penalty += min(risks[a],risks[b])*corr
        adjusted=gross+penalty
        return ExposureAssessment(gross,penalty,adjusted,adjusted<=cap)
