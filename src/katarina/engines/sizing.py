from __future__ import annotations
from dataclasses import dataclass
import math

@dataclass(frozen=True, slots=True)
class SizeResult:
    volume: float
    risk_cash: float
    valid: bool
    reason: str

class PositionSizingEngine:
    def size_active(
        self,
        *,
        active_balance: float,
        current_equity: float,
        risk_fraction: float,
        stop_distance: float,
        value_per_price_unit_per_lot: float,
        volume_min: float,
        volume_max: float,
        volume_step: float,
    ) -> SizeResult:
        """Size from protected active capital, never from reserve.

        Current equity is an additional safety ceiling so floating loss cannot
        cause sizing from capital that no longer exists.
        """
        vals=(active_balance,current_equity)
        if any(not math.isfinite(v) for v in vals) or active_balance<=0 or current_equity<=0:
            return SizeResult(0.0,0.0,False,"invalid_active_capital")
        capital=min(active_balance,current_equity)
        return self.size(
            equity=capital,
            risk_fraction=risk_fraction,
            stop_distance=stop_distance,
            value_per_price_unit_per_lot=value_per_price_unit_per_lot,
            volume_min=volume_min,
            volume_max=volume_max,
            volume_step=volume_step,
        )

    def size(self, *, equity: float, risk_fraction: float, stop_distance: float, value_per_price_unit_per_lot: float, volume_min: float, volume_max: float, volume_step: float) -> SizeResult:
        vals=(equity,risk_fraction,stop_distance,value_per_price_unit_per_lot,volume_min,volume_max,volume_step)
        if any(not math.isfinite(v) for v in vals) or equity<=0 or risk_fraction<=0 or stop_distance<=0 or value_per_price_unit_per_lot<=0 or volume_step<=0 or volume_min<=0 or volume_max<volume_min:
            return SizeResult(0.0,0.0,False,"invalid_inputs")
        risk_cash=equity*risk_fraction
        raw=risk_cash/(stop_distance*value_per_price_unit_per_lot)
        steps=math.floor((raw-volume_min)/volume_step+1e-12)
        volume=volume_min+max(0,steps)*volume_step
        volume=min(volume,volume_max)
        if raw<volume_min: return SizeResult(0.0,risk_cash,False,"below_min_volume")
        return SizeResult(round(volume,8),risk_cash,True,"ok")
