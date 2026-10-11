"""KATARINA adaptive risk budget by *usable* capital, not broker lot count.

All calculations are in native account money and normalized to USD only
for selecting a risk tier. Live execution gates remain separate.
"""
from __future__ import annotations

from dataclasses import dataclass
from math import isfinite, log
from typing import Mapping, Sequence


@dataclass(frozen=True, slots=True)
class AdaptiveRiskQuote:
    fraction: float
    risk_cash_native: float
    active_cash_native: float
    reference_cash_usd: float
    currency: str
    reason: str


class AdaptiveRiskProfile:
    def __init__(
        self,
        *,
        tiers_usd: Sequence[tuple[float, float]] = (
            (100., .02), (250., .0175), (500., .015),
            (1000., .0125), (2500., .01), (10000., .0075),
            (50000., .005), (100000., .004), (250000., .003),
        ),
        money_units_per_usd: Mapping[str, float] | None = None,
        soft_daily_drawdown: float = .05,
        soft_total_drawdown: float = .10,
        drawdown_multiplier: float = .50,
    ):
        self.tiers=tuple((float(a),float(b)) for a,b in tiers_usd)
        self.units_per_usd=dict(money_units_per_usd or {"USD":1.,"USC":100.})
        self.soft_daily_drawdown=float(soft_daily_drawdown)
        self.soft_total_drawdown=float(soft_total_drawdown)
        self.drawdown_multiplier=float(drawdown_multiplier)
        if not self.tiers or any(
            not isfinite(a) or a<=0 or not isfinite(b) or not 0<b<=.05
            for a,b in self.tiers
        ):
            raise ValueError("invalid_adaptive_tiers")
        if any(self.tiers[i][0]>=self.tiers[i+1][0] or
               self.tiers[i][1]<self.tiers[i+1][1]
               for i in range(len(self.tiers)-1)):
            raise ValueError("tiers_must_increase_in_capital_and_decrease_in_risk")
        if any(not k or not isfinite(v) or v<=0 for k,v in self.units_per_usd.items()):
            raise ValueError("invalid_account_currency_scale")
        if not (0<self.soft_daily_drawdown<.10 and 0<self.soft_total_drawdown<.20):
            raise ValueError("soft_limits_must_be_below_governor_hard_caps")
        if not 0<self.drawdown_multiplier<=1:
            raise ValueError("drawdown_multiplier_must_not_increase_risk")

    def quote(
        self,
        *,
        active_capital_native: float,
        account_currency: str,
        reference_capital_native: float | None = None,
        daily_drawdown: float = 0.,
        total_drawdown: float = 0.,
    ) -> AdaptiveRiskQuote:
        values=(active_capital_native,daily_drawdown,total_drawdown)
        if any(not isfinite(x) for x in values) or active_capital_native<=0:
            raise ValueError("invalid_adaptive_capital_or_drawdown")
        if daily_drawdown<0 or total_drawdown<0:
            raise ValueError("negative_drawdown")
        currency=str(account_currency or "").strip().upper()
        divisor=self.units_per_usd.get(currency)
        if divisor is None:
            raise ValueError("unverified_currency_units_per_usd")
        ref=active_capital_native if reference_capital_native is None else float(reference_capital_native)
        if not isfinite(ref) or ref<active_capital_native:
            raise ValueError("reference_must_not_be_lower_than_active")
        usd=ref/divisor
        if usd<=self.tiers[0][0]:
            fraction=self.tiers[0][1]
        elif usd>=self.tiers[-1][0]:
            fraction=self.tiers[-1][1]
        else:
            fraction=self.tiers[-1][1]
            for (low,fl),(high,fh) in zip(self.tiers,self.tiers[1:]):
                if low<=usd<=high:
                    mix=(log(usd)-log(low))/(log(high)-log(low))
                    fraction=fl+(fh-fl)*mix
                    break
        if daily_drawdown>=self.soft_daily_drawdown or total_drawdown>=self.soft_total_drawdown:
            fraction*=self.drawdown_multiplier
            reason="drawdown_reduction"
        else:
            reason="capital_scaled"
        return AdaptiveRiskQuote(
            fraction=fraction,
            risk_cash_native=active_capital_native*fraction,
            active_cash_native=active_capital_native,
            reference_cash_usd=usd,
            currency=currency,
            reason=reason,
        )
