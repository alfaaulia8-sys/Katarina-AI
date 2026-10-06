from __future__ import annotations
from dataclasses import dataclass
from statistics import mean
from typing import Sequence

@dataclass(frozen=True, slots=True)
class PerformanceSnapshot:
    trades: int
    expectancy_r: float
    win_rate: float
    max_drawdown_r: float
    recovery_factor: float
    degraded: bool

class PerformanceMonitor:
    @staticmethod
    def recovery_factor(net_profit_r: float, max_drawdown_r: float) -> float:
        if max_drawdown_r <= 0:
            return 0.0
        return net_profit_r / max_drawdown_r

    def evaluate(self, r_multiples: Sequence[float], *, baseline_expectancy: float=0.0, degradation_tolerance: float=0.25) -> PerformanceSnapshot:
        if not r_multiples:
            return PerformanceSnapshot(0,0.0,0.0,0.0,0.0,True)

        eq=0.0; peak=0.0; dd=0.0; wins=0
        for r in r_multiples:
            eq+=r
            peak=max(peak,eq)
            dd=max(dd,peak-eq)
            wins+=r>0

        exp=mean(r_multiples)
        threshold=baseline_expectancy-abs(baseline_expectancy)*degradation_tolerance
        recovery=self.recovery_factor(sum(r_multiples),dd)
        return PerformanceSnapshot(
            len(r_multiples),
            exp,
            wins/len(r_multiples),
            dd,
            recovery,
            exp<threshold,
        )
