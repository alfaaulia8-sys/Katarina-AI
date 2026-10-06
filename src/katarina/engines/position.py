from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import math


class ManagementAction(str, Enum):
    HOLD="HOLD"
    MODIFY_SL="MODIFY_SL"
    PARTIAL_CLOSE="PARTIAL_CLOSE"
    CLOSE="CLOSE"


@dataclass(frozen=True, slots=True)
class PositionState:
    side: str
    entry: float
    current: float
    stop: float
    risk_distance: float


@dataclass(frozen=True, slots=True)
class PositionDecision:
    action: ManagementAction
    new_stop: float|None
    fraction: float
    reason: str


@dataclass(frozen=True, slots=True)
class RRPositionState:
    position_id: str
    side: str
    entry: float
    current: float
    stop: float
    risk_distance: float
    target_rr: float
    authorized_volume: float
    current_volume: float
    volume_min: float
    volume_step: float


@dataclass(frozen=True, slots=True)
class RRManagementPlan:
    position_id: str
    current_r: float
    peak_r: float
    trigger_r: float
    target_rr: float
    partial_triggered: bool
    partial_close_volume: float
    target_remaining_volume: float
    partial_close_fraction_of_authorized: float
    new_stop: float|None
    modify_sl_required: bool
    trail_lock_fraction: float
    reason: str

    @property
    def reduce_required(self) -> bool:
        return self.partial_close_volume > 0.0


class RRProfitManager:
    """RR-based partial close + ratcheting profit protection.

    Default rule:
      target 1:N -> management trigger at (N-1)R
      on first/remaining eligible volume -> reduce to 20% of authorized volume
      runner SL locks 30% of the highest observed profit distance
      peak R is a high-water mark and never moves backward

    The manager never modifies manual positions by itself. Ownership/authority
    remains an execution-layer concern.
    """

    def __init__(
        self,
        *,
        partial_close_fraction: float = 0.80,
        trail_lock_fraction: float = 0.30,
    ):
        if not (0.0 < partial_close_fraction < 1.0):
            raise ValueError("partial_close_fraction")
        if not (0.0 < trail_lock_fraction <= 1.0):
            raise ValueError("trail_lock_fraction")
        self.partial_close_fraction=partial_close_fraction
        self.trail_lock_fraction=trail_lock_fraction

    @staticmethod
    def _floor_step(value: float, step: float) -> float:
        if step <= 0:
            return 0.0
        units=math.floor((value+1e-12)/step)
        return round(max(0.0,units*step),8)

    @staticmethod
    def _ceil_step(value: float, step: float) -> float:
        if step <= 0:
            return 0.0
        units=math.ceil((value-1e-12)/step)
        return round(max(0.0,units*step),8)

    def _target_remaining_volume(self, p: RRPositionState) -> float:
        raw=p.authorized_volume*(1.0-self.partial_close_fraction)
        target=max(p.volume_min,self._ceil_step(raw,p.volume_step))
        return round(min(target,p.authorized_volume),8)

    def evaluate(self, p: RRPositionState, *, previous_peak_r: float = 0.0) -> RRManagementPlan:
        numeric=(
            p.entry,p.current,p.stop,p.risk_distance,p.target_rr,
            p.authorized_volume,p.current_volume,p.volume_min,p.volume_step,
        )
        if (
            any(not math.isfinite(v) for v in numeric)
            or p.side not in {"BUY","SELL"}
            or p.entry <= 0
            or p.current <= 0
            or p.risk_distance <= 0
            or p.target_rr <= 1.0
            or p.authorized_volume <= 0
            or p.current_volume <= 0
            or p.volume_min <= 0
            or p.volume_step <= 0
        ):
            return RRManagementPlan(
                p.position_id,0.0,max(0.0,previous_peak_r),0.0,p.target_rr,
                False,0.0,p.current_volume,0.0,None,False,
                self.trail_lock_fraction,"invalid_position_management_state"
            )

        sign=1.0 if p.side=="BUY" else -1.0
        current_r=((p.current-p.entry)*sign)/p.risk_distance
        peak_r=max(float(previous_peak_r),current_r,0.0)
        trigger_r=max(0.0,p.target_rr-1.0)
        armed=peak_r+1e-12 >= trigger_r

        target_remaining=self._target_remaining_volume(p)
        close_volume=0.0
        if armed and p.current_volume > target_remaining+1e-12:
            desired=p.current_volume-target_remaining
            close_volume=self._floor_step(desired,p.volume_step)
            # Never submit a broker reduction that would leave an invalid remainder.
            remaining=round(p.current_volume-close_volume,8)
            if close_volume <= 0 or remaining+1e-12 < p.volume_min:
                close_volume=0.0

        actual_fraction=(
            min(1.0,close_volume/p.authorized_volume)
            if p.authorized_volume > 0 else 0.0
        )

        new_stop=None
        modify=False
        if armed:
            candidate=p.entry+sign*(self.trail_lock_fraction*peak_r*p.risk_distance)

            # Ratchet only. Never loosen an existing SL and never propose an SL
            # already beyond the current market.
            if sign > 0:
                better=candidate > p.stop+1e-12
                market_valid=candidate < p.current-1e-12
            else:
                better=candidate < p.stop-1e-12
                market_valid=candidate > p.current+1e-12

            if better and market_valid:
                new_stop=candidate
                modify=True

        if not armed:
            reason="waiting_for_rr_trigger"
        elif close_volume > 0 and modify:
            reason="partial_80_and_trail_30"
        elif close_volume > 0:
            reason="partial_80_triggered"
        elif modify:
            reason="trail_30_ratchet"
        elif p.current_volume <= target_remaining+1e-12:
            reason="partial_target_already_reached"
        else:
            reason="hold_protected"

        return RRManagementPlan(
            position_id=p.position_id,
            current_r=current_r,
            peak_r=peak_r,
            trigger_r=trigger_r,
            target_rr=p.target_rr,
            partial_triggered=armed,
            partial_close_volume=close_volume,
            target_remaining_volume=target_remaining,
            partial_close_fraction_of_authorized=actual_fraction,
            new_stop=new_stop,
            modify_sl_required=modify,
            trail_lock_fraction=self.trail_lock_fraction,
            reason=reason,
        )


class RRProfitTracker:
    """Per-position high-water tracker.

    Peak-R can be snapshotted/restored by Stage-10 persistence so restarts do
    not make a trailing stop move backward.
    """

    def __init__(self, manager: RRProfitManager | None = None):
        self.manager=manager or RRProfitManager()
        self._peak_r: dict[str,float]={}

    def evaluate(self, p: RRPositionState) -> RRManagementPlan:
        prior=self._peak_r.get(p.position_id,0.0)
        plan=self.manager.evaluate(p,previous_peak_r=prior)
        self._peak_r[p.position_id]=max(prior,plan.peak_r)
        return plan

    def remove(self, position_id: str) -> None:
        self._peak_r.pop(position_id,None)

    def snapshot(self) -> dict[str,float]:
        return dict(self._peak_r)

    def restore(self, state: dict[str,float]) -> None:
        restored={}
        for position_id,value in state.items():
            v=float(value)
            if not math.isfinite(v) or v < 0:
                raise ValueError("invalid peak_r state")
            restored[str(position_id)]=v
        self._peak_r=restored


class PositionManager:
    def __init__(self):
        self.rr_tracker=RRProfitTracker()

    def decide(self, p: PositionState, *, reversal_confirmed: bool=False, min_protect_r: float=2.0) -> PositionDecision:
        """Backward-compatible protection decision."""
        if p.risk_distance<=0:
            return PositionDecision(ManagementAction.CLOSE,None,1.0,"invalid_risk")
        sign=1 if p.side=="BUY" else -1
        r=(p.current-p.entry)*sign/p.risk_distance
        if reversal_confirmed:
            return PositionDecision(ManagementAction.CLOSE,None,1.0,"confirmed_reversal")
        if r>=min_protect_r:
            protected=p.entry+sign*(0.30*r*p.risk_distance)
            better=protected>p.stop if sign>0 else protected<p.stop
            if better:
                return PositionDecision(ManagementAction.MODIFY_SL,protected,0.0,"protect_profit")
        return PositionDecision(ManagementAction.HOLD,None,0.0,"hold")

    def decide_rr(self, p: RRPositionState) -> RRManagementPlan:
        return self.rr_tracker.evaluate(p)
