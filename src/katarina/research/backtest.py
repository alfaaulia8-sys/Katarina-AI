from __future__ import annotations
from dataclasses import dataclass
from typing import Sequence

@dataclass(frozen=True, slots=True)
class BacktestTrade:
    pnl: float
    cost: float

@dataclass(frozen=True, slots=True)
class BacktestResult:
    trades: int
    net_pnl: float
    expectancy: float
    win_rate: float
    max_drawdown: float
    recovery_factor: float
    profit_factor: float
    max_consecutive_losses: int

class BacktestingEngine:
    @staticmethod
    def recovery_factor(net_profit: float, max_drawdown: float) -> float:
        if max_drawdown <= 0:
            return 0.0
        return net_profit / max_drawdown

    def evaluate(self, trades: Sequence[BacktestTrade]) -> BacktestResult:
        equity=0.0; peak=0.0; maxdd=0.0; wins=0; net=[]
        gross_profit=0.0; gross_loss=0.0; loss_streak=0; max_loss_streak=0
        for t in trades:
            x=t.pnl-abs(t.cost)
            net.append(x)
            equity+=x
            peak=max(peak,equity)
            maxdd=max(maxdd,peak-equity)
            if x>0:
                wins+=1
                gross_profit+=x
                loss_streak=0
            elif x<0:
                gross_loss+=abs(x)
                loss_streak+=1
                max_loss_streak=max(max_loss_streak,loss_streak)
        n=len(net)
        net_pnl=sum(net)
        recovery=self.recovery_factor(net_pnl,maxdd)
        if gross_loss>0:
            pf=gross_profit/gross_loss
        elif gross_profit>0:
            pf=float("inf")
        else:
            pf=0.0
        return BacktestResult(
            n,
            net_pnl,
            net_pnl/n if n else 0.0,
            wins/n if n else 0.0,
            maxdd,
            recovery,
            pf,
            max_loss_streak,
        )
