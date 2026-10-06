from __future__ import annotations
from dataclasses import dataclass

@dataclass(frozen=True, slots=True)
class StressScenario:
    latency_ms: float=0.0
    spread_multiplier: float=1.0
    transport_up: bool=True
    data_valid: bool=True
@dataclass(frozen=True, slots=True)
class StressDecision:
    new_risk_allowed: bool
    reason: str

class StressTestEngine:
    def evaluate(self, s: StressScenario, *, latency_limit_ms: float=1000.0, spread_limit_multiplier: float=3.0) -> StressDecision:
        if not s.transport_up: return StressDecision(False,"transport_down")
        if not s.data_valid: return StressDecision(False,"invalid_data")
        if s.latency_ms>latency_limit_ms: return StressDecision(False,"latency_limit")
        if s.spread_multiplier>spread_limit_multiplier: return StressDecision(False,"spread_shock")
        return StressDecision(True,"within_stress_limits")
