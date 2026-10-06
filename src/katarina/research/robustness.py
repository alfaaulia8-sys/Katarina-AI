from __future__ import annotations
from dataclasses import dataclass
import random
from typing import Sequence

@dataclass(frozen=True, slots=True)
class RobustnessResult:
    simulations: int
    loss_probability: float
    ruin_probability: float
    p95_drawdown: float

class MonteCarloEngine:
    def simulate(self, returns: Sequence[float], *, simulations: int=500, trades_per_run: int|None=None, seed: int=1, ruin_floor: float=-0.30) -> RobustnessResult:
        if simulations<=0: raise ValueError("simulations")
        if not returns: return RobustnessResult(simulations,1.0,1.0,1.0)
        rng=random.Random(seed); n=trades_per_run or len(returns); losses=ruins=0; dds=[]
        for _ in range(simulations):
            eq=0.0; peak=0.0; maxdd=0.0
            for _ in range(n):
                eq += rng.choice(returns); peak=max(peak,eq); maxdd=max(maxdd,peak-eq)
            losses += eq<0; ruins += eq<=ruin_floor; dds.append(maxdd)
        dds.sort(); idx=min(len(dds)-1,int(0.95*(len(dds)-1)))
        return RobustnessResult(simulations,losses/simulations,ruins/simulations,dds[idx])
