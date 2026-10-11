"""Conservative research-only Stage 16/17 sizing; never creates orders."""
from __future__ import annotations
from dataclasses import dataclass
from decimal import Decimal, ROUND_FLOOR
from math import isfinite
from katarina.engines.risk import RiskAction, RiskGovernor, RiskRequest


@dataclass(frozen=True)
class BrokerFacts:
    currency: str
    contract_revision: int
    loss_per_price_unit_per_lot: float
    min_volume: float
    max_volume: float
    volume_step: float
    margin_per_lot: float
    verified: bool = False


@dataclass(frozen=True)
class TradingCosts:
    spread_distance: float
    adverse_slippage_distance: float
    round_trip_fee_per_lot: float
    verified: bool = False


@dataclass(frozen=True)
class AccountFacts:
    native_currency: str
    active_capital: float
    equity: float
    peak_reference_capital: float
    available_margin: float
    committed_risk_fraction: float = 0.0
    daily_drawdown: float = 0.0
    total_drawdown: float = 0.0
    healthy: bool = True
    reconciled: bool = True
    unbounded_risk: bool = False
    uncertainty: float | None = None
    expected_rr: float | None = None
    verified: bool = False


@dataclass(frozen=True)
class Qualification:
    eligible_for_research: bool
    reason: str
    volume: float = 0.0
    fraction: float = 0.0
    budget_native: float = 0.0
    buffered_loss_native: float = 0.0
    margin_native: float = 0.0
    live_execution_authorized: bool = False


class ResearchCostMarginGate:
    """Use *confirmed* native-money facts; no account/market autodiscovery."""

    def __init__(self, governor: RiskGovernor):
        self.governor = governor

    def qualify(self, *, account: AccountFacts, broker: BrokerFacts,
                costs: TradingCosts, side: str, entry: float, stop: float) -> Qualification:
        reject = lambda reason: Qualification(False, reason)
        if not (account.verified and broker.verified and costs.verified):
            return reject("unverified_account_contract_or_cost")
        if account.uncertainty is None or account.expected_rr is None:
            return reject("missing_signal_quality_evidence")
        if not account.native_currency or account.native_currency != broker.currency:
            return reject("currency_unverified_or_mismatch")
        if side not in ("BUY", "SELL"):
            return reject("invalid_side")
        values = (account.active_capital, account.equity, account.peak_reference_capital,
                  account.available_margin, account.committed_risk_fraction,
                  account.daily_drawdown, account.total_drawdown,
                  account.uncertainty, account.expected_rr,
                  broker.loss_per_price_unit_per_lot, broker.min_volume,
                  broker.max_volume, broker.volume_step, broker.margin_per_lot,
                  costs.spread_distance, costs.adverse_slippage_distance,
                  costs.round_trip_fee_per_lot, entry, stop)
        if any(not isfinite(v) for v in values):
            return reject("nonfinite_evidence")
        capital = min(account.active_capital, account.equity)
        if (capital <= 0 or account.available_margin <= 0 or
            account.peak_reference_capital < capital or broker.contract_revision < 1 or
            broker.loss_per_price_unit_per_lot <= 0 or broker.min_volume <= 0 or
            broker.max_volume < broker.min_volume or broker.volume_step <= 0 or
            broker.margin_per_lot <= 0 or min(entry, stop) <= 0 or
            min(costs.spread_distance, costs.adverse_slippage_distance,
                costs.round_trip_fee_per_lot) < 0):
            return reject("invalid_account_or_broker_spec")
        if (side == "BUY" and stop >= entry) or (side == "SELL" and stop <= entry):
            return reject("stop_missing_or_wrong_side")
        per_lot = ((abs(entry-stop) + costs.spread_distance +
                    costs.adverse_slippage_distance) * broker.loss_per_price_unit_per_lot +
                   costs.round_trip_fee_per_lot)
        if not isfinite(per_lot) or per_lot <= 0:
            return reject("invalid_buffered_loss")
        risk = self.governor.evaluate(RiskRequest(
            None, account.committed_risk_fraction, account.total_drawdown,
            account.uncertainty, account.expected_rr, account.healthy,
            account.reconciled, account.daily_drawdown,
            account.unbounded_risk, capital, account.peak_reference_capital,
            account.native_currency))
        if risk.action not in (RiskAction.APPROVE, RiskAction.REDUCE):
            return reject("governor_" + risk.reason)
        budget = capital*risk.approved_fraction
        usable_margin = account.available_margin*.90
        affordable = min(broker.max_volume, budget/per_lot,
                         usable_margin/broker.margin_per_lot)
        if affordable < broker.min_volume:
            return reject("min_lot_exceeds_risk_or_margin")
        minimum = Decimal(str(broker.min_volume))
        step = Decimal(str(broker.volume_step))
        steps = ((Decimal(str(affordable))-minimum)/step).to_integral_value(rounding=ROUND_FLOOR)
        volume = float(minimum+steps*step)
        buffered_loss, margin = volume*per_lot, volume*broker.margin_per_lot
        if (volume < broker.min_volume or volume > broker.max_volume or
            buffered_loss > budget+1e-9 or margin > usable_margin+1e-9):
            return reject("cost_or_margin_exceeds_budget")
        return Qualification(True, "qualified_for_research_only", volume,
                             risk.approved_fraction, budget, buffered_loss, margin)
