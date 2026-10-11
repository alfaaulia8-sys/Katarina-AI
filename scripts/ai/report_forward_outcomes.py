"""Read-only descriptive markout report. Never a strategy acceptance gate."""
import argparse
import json
import sqlite3
from pathlib import Path


def report(db):
    groups = {}
    query = """SELECT symbol,side,horizon,context,status,markout_bps,markout_atr,
               midpoint_bps FROM forward_markouts"""
    for symbol, side, horizon, context, status, bps, atr, mid in db.execute(query):
        metadata = json.loads(context)
        ready = bool((metadata.get("context") or {}).get("ready"))
        regime = metadata.get("regime") or "UNKNOWN"
        detail = metadata.get("regime_detail") or "UNKNOWN"
        hypotheses = metadata.get("shadow_hypotheses") or []
        match = [h.get("family") for h in hypotheses if
                 isinstance(h, dict) and h.get("side") == side and
                 h.get("research_only") is True]
        family = match[0] if len(match) == 1 and isinstance(match[0], str) else "NONE"
        key = (symbol, side, horizon, ready, regime, detail, family)
        group = groups.setdefault(key, dict(symbol=symbol, side=side,
            horizon_seconds=horizon, context_ready=ready, regime=regime,
            regime_detail=detail, shadow_family=family,
            pending=0, missing_exit=0, observed=0,
            spread_markout_bps_sum=0., atr_markout_sum=0., midpoint_bps_sum=0.))
        group[status.lower()] += 1
        if status == "OBSERVED":
            group["spread_markout_bps_sum"] += bps
            group["atr_markout_sum"] += atr
            group["midpoint_bps_sum"] += mid
    rows = []
    for key in sorted(groups):
        group = groups[key]
        count = group["observed"]
        for name in ("spread_markout_bps", "atr_markout", "midpoint_bps"):
            total = group.pop(name+"_sum")
            group[name+"_mean"] = total/count if count else None
        group["status"] = "DESCRIPTIVE_ONLY" if count else "AWAITING_VALID_QUOTES"
        rows.append(group)
    return dict(kind="forward_quote_markout_not_strategy_pnl",
        limitations=["Hypothetical breakout candidates are neither fills nor tested profitable strategies.",
                     "Regime classes are research hypotheses, not proven entry signals.",
                     "Overlapping observations are not independent trades.",
                     "No actual fills, SL/TP path, commission or slippage.",
                     "Differences between context groups do not prove causation.",
                     "No model training, promotion or live authorization."],
        groups=rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", required=True)
    args = parser.parse_args()
    uri = Path(args.database).resolve().as_uri()+"?mode=ro"
    with sqlite3.connect(uri, uri=True) as db:
        result = report(db)
    print(json.dumps(result, indent=2, allow_nan=False))


if __name__ == "__main__":
    main()
