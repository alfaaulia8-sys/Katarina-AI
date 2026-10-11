"""Preregistered, cost-stressed research alpha survival gate.

A candidate can pass for SHADOW RESEARCH only with a future, independently
attested closed holdout. No broker interface, order execution, or live authority.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from hashlib import sha256
from math import isfinite
from random import Random
from collections import defaultdict
import re


REGIME_ROUTES = {
    "TREND_UP": ("BUY", "TREND_PULLBACK"),
    "TREND_DOWN": ("SELL", "TREND_PULLBACK"),
    "PULLBACK_UP": ("BUY", "TREND_PULLBACK"),
    "PULLBACK_DOWN": ("SELL", "TREND_PULLBACK"),
    "BREAKOUT_UP": ("BUY", "BREAKOUT_RETEST"),
    "BREAKOUT_DOWN": ("SELL", "BREAKOUT_RETEST"),
    "REVERSAL_UP": ("BUY", "REVERSAL_RECLAIM"),
    "REVERSAL_DOWN": ("SELL", "REVERSAL_RECLAIM"),
    "SIDEWAYS": ("BOTH", "RANGE_FADE"),
    "VOLATILITY_SHOCK": ("WAIT", "OBSERVE"),
    "TRANSITION": ("WAIT", "OBSERVE"),
    "UNKNOWN": ("WAIT", "OBSERVE"),
}

@dataclass(frozen=True)
class FrozenHypothesis:
    symbol: str
    market_state: str
    side: str
    playbook: str
    freeze_at: datetime
    holdout_start: datetime
    holdout_end: datetime
    dataset_sha256: str
    preregistered_tests: int
    extra_cost_r: float = .10
    independent_holdout_attested: bool = False
    actual_all_in_cost_attested: bool = False
    broker_contract_attested: bool = False


@dataclass(frozen=True)
class ClosedOutcome:
    event_id: str
    entry_at: datetime
    exit_at: datetime
    known_at: datetime
    dataset_sha256: str
    net_r_after_reported_costs: float


def _utc(value):
    if not isinstance(value, datetime) or value.tzinfo is None:
        raise ValueError("naive_or_invalid_time")
    return value.astimezone(timezone.utc)


def _blocked(reason, *, checked=0, measurements=None):
    return {
        "status": "BLOCKED_" + reason,
        "shadow_research_qualified": False,
        "alpha_proven_for_live": False,
        "live_execution_authorized": False,
        "checked_outcomes": checked,
        "measurements": measurements or {},
    }


def assess(hypothesis: FrozenHypothesis, outcomes, *, audit_at: datetime,
           resamples: int = 2048, min_trades: int = 60,
           min_weeks: int = 20, min_months: int = 5):
    """Conservative weekly-block bootstrap screen, not a predictive guarantee.

    Require 100% new unobserved holdout, with preregistration and real broker
    economics attested externally. All statuses keep live trading disabled.
    """
    audit_at = _utc(audit_at)
    frozen, start, end = (_utc(x) for x in (
        hypothesis.freeze_at, hypothesis.holdout_start, hypothesis.holdout_end))
    expected = REGIME_ROUTES.get(hypothesis.market_state)
    if not hypothesis.symbol or expected is None:
        return _blocked("INVALID_REGIME_ROUTE")
    if expected[0] == "WAIT":
        return _blocked("REGIME_NO_TRADE")
    if (hypothesis.side not in ("BUY", "SELL")
        or (expected[0] != "BOTH" and hypothesis.side != expected[0])
        or hypothesis.playbook != expected[1]):
        return _blocked("INVALID_REGIME_ROUTE")
    if not (frozen < start < end and hypothesis.preregistered_tests >= 1
            and isfinite(hypothesis.extra_cost_r) and
            0 <= hypothesis.extra_cost_r < 10 and
            re.fullmatch("[0-9a-f]{64}", hypothesis.dataset_sha256)):
        return _blocked("INVALID_HYPOTHESIS_OR_FREEZE")
    if not (hypothesis.independent_holdout_attested and
            hypothesis.actual_all_in_cost_attested and
            hypothesis.broker_contract_attested):
        return _blocked("UNATTESTED_REAL_HOLDOUT_AND_COSTS")
    if audit_at < end:
        return _blocked("HOLDOUT_NOT_FINISHED")
    if not (resamples >= 128 and 20 <= min_trades and
            8 <= min_weeks and 3 <= min_months):
        raise ValueError("invalid_evidence_gate_parameters")
    rows = sorted(tuple(outcomes), key=lambda x: _utc(x.entry_at))
    if not rows:
        return _blocked("NO_OUTCOMES")
    known_events = set()
    last_exit = None
    weeks = defaultdict(list)
    months = set()
    net_values = []
    for row in rows:
        entry, exit_time, learned = (_utc(x) for x in
                                     (row.entry_at, row.exit_at, row.known_at))
        if (not row.event_id or row.event_id in known_events
            or row.dataset_sha256 != hypothesis.dataset_sha256
            or not (start <= entry < exit_time <= end)
            or not (exit_time <= learned <= audit_at)
            or (last_exit is not None and entry < last_exit)
            or not isfinite(row.net_r_after_reported_costs)):
            return _blocked("CORRUPT_OVERLAPPING_OR_LOOKAHEAD_EVIDENCE")
        known_events.add(row.event_id)
        last_exit = exit_time
        cost_stressed_r = row.net_r_after_reported_costs - hypothesis.extra_cost_r
        net_values.append(cost_stressed_r)
        iso = entry.isocalendar()
        weeks[(iso.year, iso.week)].append(cost_stressed_r)
        months.add((entry.year, entry.month))
    n = len(net_values)
    week_returns = [sum(v) for v in weeks.values()]
    pos = sum(x for x in net_values if x > 0)
    neg = -sum(x for x in net_values if x < 0)
    gross = sum(net_values)
    cumulative = peak = max_drawdown = 0.
    for value in net_values:
        cumulative += value
        peak = max(peak, cumulative)
        max_drawdown = max(max_drawdown, peak - cumulative)
    # Preserve no-loss samples as suspicious, rather than infinite PF.
    profit_factor = pos/neg if neg else None
    top_five_excluded = gross - sum(sorted(net_values, reverse=True)[:5])
    positives = sum(value > 0 for value in week_returns)
    # Weekly resampling retains intraweek dependence, not cross-week regimes.
    rng = Random(int(sha256(
        (hypothesis.dataset_sha256 + hypothesis.symbol
         + hypothesis.market_state + hypothesis.side).encode()).hexdigest()[:16], 16))
    blocks = tuple(weeks.values())
    means = []
    for _ in range(resamples):
        sample = [blocks[rng.randrange(len(blocks))] for __ in blocks]
        means.append(sum(sum(block) for block in sample) /
                     sum(len(block) for block in sample))
    means.sort()
    alpha = .05/hypothesis.preregistered_tests
    lower = means[max(0, int(alpha*resamples)-1)]
    stats = {
        "trades": n, "weeks": len(weeks), "months": len(months),
        "mean_net_stressed_r": round(gross/n, 6),
        "profit_factor": round(profit_factor, 6) if profit_factor is not None else None,
        "top_five_excluded_net_r": round(top_five_excluded, 6),
        "positive_week_fraction": round(positives/len(weeks), 6),
        "max_drawdown_r": round(max_drawdown, 6),
        "weekly_block_bootstrap_lower_mean_r": round(lower, 6),
        "familywise_alpha_per_test": round(alpha, 8),
        "cost_stress_extra_r": hypothesis.extra_cost_r,
        "note": "Descriptive bootstrap screen; not a guarantee of predictive alpha",
    }
    gates = {
        "trades": n >= min_trades,
        "weeks": len(weeks) >= min_weeks,
        "months": len(months) >= min_months,
        "profit_factor": profit_factor is not None and profit_factor >= 1.25,
        "mean": gross/n > 0,
        "top5": top_five_excluded > 0,
        "positive_weeks": positives/len(weeks) >= .55,
        "drawdown": max_drawdown <= 12,
        "block_bootstrap": lower > 0,
    }
    stats["gates"] = gates
    result = _blocked("STATISTICAL_SCREEN", checked=n, measurements=stats)
    if all(gates.values()):
        result["status"] = "PASS_SHADOW_RESEARCH_ONLY"
        result["shadow_research_qualified"] = True
    return result
