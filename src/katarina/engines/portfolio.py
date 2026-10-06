from __future__ import annotations
from dataclasses import dataclass
from typing import Mapping

@dataclass(frozen=True, slots=True)
class PortfolioAllocation:
    approved: Mapping[str,float]
    rejected: tuple[str,...]
    total_risk: float

class PortfolioEngine:
    def allocate(self, requested: Mapping[str,float], *, max_total_risk: float=0.08, per_symbol_cap: float=0.05) -> PortfolioAllocation:
        remaining=max_total_risk; approved={}; rejected=[]
        for symbol in sorted(requested):
            req=max(0.0,float(requested[symbol])); take=min(req,per_symbol_cap,remaining)
            if take>0: approved[symbol]=take; remaining-=take
            if take+1e-12<req: rejected.append(symbol)
        return PortfolioAllocation(approved,tuple(rejected),sum(approved.values()))
