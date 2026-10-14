from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from math import isfinite
from typing import Iterable, Mapping, Any

from katarina.validation.engine import ValidationDisposition, ValidationResult


class PositionOrigin(str, Enum):
    KATARINA = "KATARINA"
    MANUAL_DESKTOP = "MANUAL_DESKTOP"
    MANUAL_MOBILE = "MANUAL_MOBILE"
    MANUAL_WEB = "MANUAL_WEB"
    FOREIGN_EA = "FOREIGN_EA"
    BROKER_OPERATION = "BROKER_OPERATION"
    UNKNOWN = "UNKNOWN"


ORIGIN_BY_KAT1 = {
    0: PositionOrigin.UNKNOWN.value,
    1: PositionOrigin.KATARINA.value,
    2: PositionOrigin.MANUAL_DESKTOP.value,
    3: PositionOrigin.MANUAL_MOBILE.value,
    4: PositionOrigin.MANUAL_WEB.value,
    5: PositionOrigin.FOREIGN_EA.value,
    6: PositionOrigin.BROKER_OPERATION.value,
}
SIDE_BY_KAT1 = {0: "NONE", 1: "BUY", 2: "SELL"}


@dataclass(frozen=True, slots=True)
class SymbolRiskSpec:
    """Account-native loss value for one broker tick and one lot."""
    tick_size: float
    tick_value_loss: float


@dataclass(frozen=True, slots=True)
class PositionRiskInput:
    position_id: str
    origin: str | int
    side: str | int
    volume: float
    open_price: float
    current_price: float
    stop_loss: float | None
    symbol_spec: SymbolRiskSpec | None
    broker_loss_to_sl: float | None = None


@dataclass(frozen=True, slots=True)
class PositionRisk:
    position_id: str
    origin: str
    risk_cash: float
    bounded: bool
    reason: str


@dataclass(frozen=True, slots=True)
class AccountRiskAssessment:
    equity: float
    open_risk_cash: float
    open_risk_fraction: float
    external_risk_cash: float
    external_risk_fraction: float
    position_count: int
    external_position_count: int
    unbounded_position_ids: tuple[str, ...]
    position_risks: tuple[PositionRisk, ...]

    @property
    def has_unbounded_risk(self) -> bool:
        return bool(self.unbounded_position_ids)


class SharedAccountRiskEngine:
    """Calculates remaining loss-to-SL for every open account position."""

    EXTERNAL_ORIGINS = {
        PositionOrigin.MANUAL_DESKTOP.value,
        PositionOrigin.MANUAL_MOBILE.value,
        PositionOrigin.MANUAL_WEB.value,
        PositionOrigin.FOREIGN_EA.value,
        PositionOrigin.UNKNOWN.value,
    }

    @staticmethod
    def _norm_origin(origin: str | int) -> str:
        if isinstance(origin, int):
            return ORIGIN_BY_KAT1.get(origin, PositionOrigin.UNKNOWN.value)
        value=str(origin or "UNKNOWN").upper()
        valid={x.value for x in PositionOrigin}
        return value if value in valid else PositionOrigin.UNKNOWN.value

    @staticmethod
    def _norm_side(side: str | int) -> str:
        if isinstance(side, int):
            return SIDE_BY_KAT1.get(side, "NONE")
        return str(side or "").upper()

    def position_risk(self, p: PositionRiskInput) -> PositionRisk:
        origin=self._norm_origin(p.origin)
        side=self._norm_side(p.side)

        if origin == PositionOrigin.BROKER_OPERATION.value:
            return PositionRisk(p.position_id,origin,0.0,True,"broker_operation_not_exposure")

        values=(p.volume,p.open_price,p.current_price)
        if any(not isfinite(v) for v in values) or p.volume <= 0 or p.open_price <= 0:
            return PositionRisk(p.position_id,origin,0.0,False,"invalid_position_values")
        if side not in {"BUY","SELL"}:
            return PositionRisk(p.position_id,origin,0.0,False,"unknown_position_side")
        if p.stop_loss is None or not isfinite(p.stop_loss) or p.stop_loss <= 0:
            return PositionRisk(p.position_id,origin,0.0,False,"missing_stop_loss")

        mark=p.current_price if p.current_price > 0 else p.open_price

        # A stop beyond the CURRENT market in a protecting direction has no
        # remaining downside from current equity. A stop merely beyond entry
        # still has giveback risk from current price to that stop.
        if side == "BUY" and p.stop_loss >= mark:
            return PositionRisk(p.position_id,origin,0.0,True,"stop_protects_current_equity")
        if side == "SELL" and p.stop_loss <= mark:
            return PositionRisk(p.position_id,origin,0.0,True,"stop_protects_current_equity")

        if p.broker_loss_to_sl is not None:
            if not isfinite(p.broker_loss_to_sl) or p.broker_loss_to_sl < 0:
                return PositionRisk(p.position_id,origin,0.0,False,"invalid_broker_loss_to_sl")
            return PositionRisk(
                p.position_id,origin,float(p.broker_loss_to_sl),True,"broker_ordercalcprofit"
            )

        spec=p.symbol_spec
        if spec is None:
            return PositionRisk(p.position_id,origin,0.0,False,"missing_symbol_risk_spec")
        if (
            not isfinite(spec.tick_size)
            or not isfinite(spec.tick_value_loss)
            or spec.tick_size <= 0
            or spec.tick_value_loss <= 0
        ):
            return PositionRisk(p.position_id,origin,0.0,False,"invalid_symbol_risk_spec")

        distance=abs(mark-p.stop_loss)
        ticks=distance/spec.tick_size
        risk_cash=ticks*spec.tick_value_loss*p.volume
        if not isfinite(risk_cash) or risk_cash < 0:
            return PositionRisk(p.position_id,origin,0.0,False,"risk_calculation_failed")
        return PositionRisk(p.position_id,origin,risk_cash,True,"symbol_spec_fallback")

    def assess(self, positions: Iterable[PositionRiskInput], *, equity: float) -> AccountRiskAssessment:
        items=tuple(positions)
        risks=tuple(self.position_risk(p) for p in items)

        if not isfinite(equity) or equity <= 0:
            unbounded=tuple(r.position_id for r in risks) or ("ACCOUNT_EQUITY_INVALID",)
            return AccountRiskAssessment(
                equity,0.0,1.0,0.0,1.0,len(items),0,unbounded,risks
            )

        open_cash=sum(r.risk_cash for r in risks if r.bounded)
        external_cash=sum(
            r.risk_cash for r in risks
            if r.bounded and r.origin in self.EXTERNAL_ORIGINS
        )
        unbounded=tuple(r.position_id for r in risks if not r.bounded)
        external_count=sum(1 for r in risks if r.origin in self.EXTERNAL_ORIGINS)

        return AccountRiskAssessment(
            equity=equity,
            open_risk_cash=open_cash,
            open_risk_fraction=open_cash/equity,
            external_risk_cash=external_cash,
            external_risk_fraction=external_cash/equity,
            position_count=len(items),
            external_position_count=external_count,
            unbounded_position_ids=unbounded,
            position_risks=risks,
        )


class SharedAccountRiskTracker:
    """Latest reconciled open-position view keyed by stable position identifier."""

    def __init__(self, engine: SharedAccountRiskEngine | None = None):
        self.engine=engine or SharedAccountRiskEngine()
        self._positions: dict[str, PositionRiskInput]={}

    def upsert(self, position: PositionRiskInput) -> None:
        if not position.position_id:
            raise ValueError("position_id required")
        self._positions[position.position_id]=position

    def remove(self, position_id: str) -> None:
        self._positions.pop(position_id,None)

    def clear(self) -> None:
        self._positions.clear()

    def assess(self, *, equity: float) -> AccountRiskAssessment:
        return self.engine.assess(self._positions.values(),equity=equity)

    @property
    def position_count(self) -> int:
        return len(self._positions)


@dataclass(frozen=True, slots=True)
class Kat1SymbolRiskProfile:
    instrument_id: int
    spec_revision: int
    price_scale: int
    volume_scale: int
    tick_size_units: int
    tick_value_loss_units: int


class Kat1SharedAccountRiskRuntime:
    """Binds ACCEPTED Stage-08 KAT1 state to shared-account risk.

    It consumes ValidationResult rather than raw wire events, so rejected or
    quarantined broker data never enters the authoritative risk calculation.
    """

    def __init__(self):
        self.tracker=SharedAccountRiskTracker()
        self._symbol_specs: dict[int, Kat1SymbolRiskProfile]={}
        self._equity_native: float | None=None
        self._money_scale: int | None=None

    @staticmethod
    def _mapping(payload: Any) -> Mapping[str, Any] | None:
        return payload if isinstance(payload, Mapping) else None

    @staticmethod
    def _scaled(units: int, scale: int) -> float:
        return float(units) * (10.0 ** (-int(scale)))

    def observe(self, result: ValidationResult) -> bool:
        if result.disposition is not ValidationDisposition.ACCEPT:
            return False
        event=result.event
        payload=self._mapping(event.payload)
        if payload is None:
            return False

        if event.topic == "account.state":
            if "equity_units" not in payload or "account_currency_digits" not in payload:
                self._equity_native=None
                self._money_scale=None
                return False
            self._money_scale=int(payload["account_currency_digits"])
            self._equity_native=self._scaled(int(payload["equity_units"]),self._money_scale)
            return True

        if event.topic == "symbol.spec":
            required=(
                "instrument_id","spec_revision","price_scale","volume_scale",
                "tick_size_units","tick_value_loss_units",
            )
            if any(name not in payload for name in required):
                return False
            profile=Kat1SymbolRiskProfile(
                instrument_id=int(payload["instrument_id"]),
                spec_revision=int(payload["spec_revision"]),
                price_scale=int(payload["price_scale"]),
                volume_scale=int(payload["volume_scale"]),
                tick_size_units=int(payload["tick_size_units"]),
                tick_value_loss_units=int(payload["tick_value_loss_units"]),
            )
            self._symbol_specs[profile.instrument_id]=profile
            return True

        if event.topic == "position.state":
            pid=str(int(payload.get("position_identifier",0)))
            if not pid or pid == "0":
                return False

            change_kind=int(payload.get("change_kind",0))
            if change_kind == 2:
                self.tracker.remove(pid)
                return True
            if change_kind != 1:
                return False

            instrument_id=int(payload.get("instrument_id",0))
            spec_revision=int(payload.get("spec_revision",0))
            spec=self._symbol_specs.get(instrument_id)

            symbol_risk: SymbolRiskSpec | None=None
            if (
                spec is not None
                and spec.spec_revision == spec_revision
                and self._money_scale is not None
            ):
                symbol_risk=SymbolRiskSpec(
                    tick_size=self._scaled(spec.tick_size_units,spec.price_scale),
                    tick_value_loss=self._scaled(spec.tick_value_loss_units,self._money_scale),
                )

            if spec is None:
                price_scale=0
                volume_scale=0
            else:
                price_scale=spec.price_scale
                volume_scale=spec.volume_scale

            sl_units=int(payload.get("sl_units",0))
            position=PositionRiskInput(
                position_id=pid,
                origin=int(payload.get("origin_class",0)),
                side=int(payload.get("side",0)),
                volume=self._scaled(int(payload.get("volume_units",0)),volume_scale),
                open_price=self._scaled(int(payload.get("open_price_units",0)),price_scale),
                current_price=self._scaled(int(payload.get("current_price_units",0)),price_scale),
                stop_loss=None if sl_units <= 0 else self._scaled(sl_units,price_scale),
                symbol_spec=symbol_risk,
            )
            self.tracker.upsert(position)
            return True

        return False

    def assessment(self) -> AccountRiskAssessment:
        equity=self._equity_native if self._equity_native is not None else 0.0
        return self.tracker.assess(equity=equity)

    @property
    def equity_native(self) -> float | None:
        return self._equity_native


@dataclass(frozen=True, slots=True)
class PositionPnLChange:
    """Broker-ledger realized and broker-marked floating changes, account units."""
    position_id: str
    origin: str
    realized_delta: float
    floating_delta: float


@dataclass(frozen=True, slots=True)
class BrokerLossAttribution:
    """Arithmetic reconciliation ONLY; not authenticated live broker authority."""
    balanced: bool
    owner_loss_cash: float
    katarina_loss_cash: float
    unknown_loss_cash: float
    unexplained_cash: float
    reason: str


class BrokerPnLReconciler:
    """Conservatively attribute account-wide realized+floating P/L movement.

    Position changes must be derived from *complete* broker deal history and
    marked snapshots, including closed trades, commission, swap and fees.
    This function cannot authenticate a broker or certify event completeness.
    Those are mandatory separate runtime integration gates.
    """

    OWNER_ORIGINS=frozenset({
        "MANUAL_DESKTOP","MANUAL_MOBILE","MANUAL_WEB",
    })

    @classmethod
    def reconcile(
        cls, *, previous_equity: float, current_equity: float,
        external_cash_flow: float, changes: Iterable[PositionPnLChange],
        smallest_currency_unit: float = 0.01,
    ) -> BrokerLossAttribution:
        vals=(previous_equity,current_equity,external_cash_flow,smallest_currency_unit)
        if (any(not isfinite(v) for v in vals)
                or previous_equity<=0 or current_equity<=0
                or not 0<smallest_currency_unit<=1):
            raise ValueError("invalid_broker_account_snapshot")
        rows=tuple(changes)
        seen=set()
        owner=katarina=unknown=0.0
        unknown_origin_present=False
        signed_total=0.0
        for row in rows:
            if not isinstance(row,PositionPnLChange) or not row.position_id:
                raise ValueError("invalid_broker_position_delta")
            if row.position_id in seen:
                raise ValueError("duplicate_broker_position_delta")
            seen.add(row.position_id)
            if any(not isfinite(v) for v in (row.realized_delta,row.floating_delta)):
                raise ValueError("nonfinite_broker_position_delta")
            contribution=row.realized_delta+row.floating_delta
            signed_total+=contribution
            origin=SharedAccountRiskEngine._norm_origin(row.origin)
            if origin in cls.OWNER_ORIGINS:
                owner+=contribution
            elif origin=="KATARINA":
                katarina+=contribution
            else:
                # Includes foreign-EA, UNKNOWN and broker operations: their
                # activity must never be reclassified as Owner-caused.
                unknown+=contribution
                unknown_origin_present=True
        actual=current_equity-previous_equity-external_cash_flow
        diff=actual-signed_total
        balanced=abs(diff)<=smallest_currency_unit/2+1e-9
        # Unknown-origin activity may offset a loss or falsely explain DD.
        # Require no unmatched source P/L before claiming Owner causation.
        if not balanced:
            reason="account_equity_profit_reconciliation_failed"
        elif unknown_origin_present:
            reason="unknown_or_foreign_origin_not_attributable"
        elif not rows:
            reason="empty_position_history"
        else:
            reason="arithmetic_balanced_not_broker_authenticated"
        return BrokerLossAttribution(
            balanced=balanced and reason=="arithmetic_balanced_not_broker_authenticated",
            owner_loss_cash=max(0.0,-owner),
            katarina_loss_cash=max(0.0,-katarina),
            unknown_loss_cash=max(0.0,-unknown),
            unexplained_cash=diff,
            reason=reason,
        )
