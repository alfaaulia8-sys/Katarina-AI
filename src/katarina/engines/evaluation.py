from __future__ import annotations
from dataclasses import dataclass

@dataclass(frozen=True, slots=True)
class TradeEvaluation:
    r_multiple: float
    mae_r: float
    mfe_r: float
    cost_r: float
    decision_quality: float

class TradeEvaluationEngine:
    def evaluate(self, *, side: str, entry: float, exit_price: float, stop_distance: float, lowest: float, highest: float, total_cost: float, evidence_score: float, uncertainty: float) -> TradeEvaluation:
        if stop_distance<=0: raise ValueError("stop_distance")
        sign=1 if side=="BUY" else -1
        gross=(exit_price-entry)*sign/stop_distance
        cost_r=max(0.0,total_cost/stop_distance)
        r=gross-cost_r
        adverse=((entry-lowest) if sign>0 else (highest-entry))/stop_distance
        favorable=((highest-entry) if sign>0 else (entry-lowest))/stop_distance
        quality=max(0.0,min(1.0,0.6*evidence_score+0.4*(1.0-uncertainty)))
        return TradeEvaluation(r,max(0.0,adverse),max(0.0,favorable),cost_r,quality)
