from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

from katarina.research.backtest import BacktestResult
from katarina.research.robustness import MonteCarloEngine, RobustnessResult
from katarina.research.walkforward import WalkForwardEngine, WalkForwardResult


@dataclass(frozen=True, slots=True)
class StrategyValidationResult:
    backtest: BacktestResult
    walkforward: WalkForwardResult
    monte_carlo: RobustnessResult
    passed: bool
    reasons: tuple[str,...]


class StrategyValidationSuite:
    def evaluate(
        self,
        r_multiples:Sequence[float],
        backtest:BacktestResult,
        *,
        train_size:int,
        test_size:int,
        simulations:int=500,
        min_trades:int=20,
        min_profit_factor:float=1.20,
        min_recovery_factor:float=1.25,
        min_walkforward_stability:float=.60,
        max_ruin_probability:float=.05,
    )->StrategyValidationResult:
        wf=WalkForwardEngine().split(r_multiples,train_size=train_size,test_size=test_size)
        mc=MonteCarloEngine().simulate(r_multiples,simulations=simulations,seed=17,ruin_floor=-10.0)
        reasons=[]
        if backtest.trades<min_trades:reasons.append("insufficient_trades")
        if backtest.profit_factor<min_profit_factor:reasons.append("profit_factor")
        if backtest.recovery_factor<min_recovery_factor:reasons.append("recovery_factor")
        if wf.stability<min_walkforward_stability:reasons.append("walkforward_stability")
        if mc.ruin_probability>max_ruin_probability:reasons.append("monte_carlo_ruin")
        return StrategyValidationResult(backtest,wf,mc,not reasons,tuple(reasons))
