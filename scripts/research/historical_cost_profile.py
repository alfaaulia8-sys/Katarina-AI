"""Cost feasibility diagnostics for historical bid/ask quoted proposals.

Profiles observed spreads against M1 ATR without relaxing the production
screening rule or selecting new strategies on reused historical data.
"""
from __future__ import annotations
import argparse
import json
import math
from collections import defaultdict
from pathlib import Path
from statistics import mean,median

def percentile(values,p):
    if not values:
        return None
    a=sorted(values)
    rank=(len(a)-1)*p
    lo=int(rank)
    hi=min(lo+1,len(a)-1)
    return a[lo]*(hi-rank)+a[hi]*(rank-lo)

def profile(paths):
    rows=defaultdict(list)
    window_counts=[]
    for path in paths:
        obj=json.loads(Path(path).read_text(encoding="utf-8"))
        if obj.get("report_version") != "historical_tick_shadow_v1":
            raise ValueError("unsupported_evidence_version")
        items=[s for item in obj["symbols"] for s in item.get("signals",[])]
        if obj["signals_observed"]!=len(items):
            raise ValueError("inconsistent_evidence_count")
        window_counts.append({"start":obj["period"]["start"],
                              "end_exclusive":obj["period"]["end_exclusive"],
                              "signals":len(items)})
        for s in items:
            cost=float(s["entry_spread_atr"])
            quoted=float(s["quoted_markout_bps"])
            if not (math.isfinite(cost) and cost>=0 and math.isfinite(quoted)):
                raise ValueError("invalid_quote_cost")
            if bool(s["cost_screen_pass"])!=(cost<=.15):
                raise ValueError("original_spread_gate_mismatch")
            rows[(s["symbol"],s["side"])].append(s)
    groups=[]
    for (symbol,side),sample in sorted(rows.items()):
        costs=[r["entry_spread_atr"] for r in sample]
        passed=[r for r in sample if r["cost_screen_pass"]]
        skipped=[r for r in sample if not r["cost_screen_pass"]]
        groups.append(dict(symbol=symbol,side=side,
            observations=len(sample),spread_pass_count=len(passed),
            spread_reject_count=len(skipped),
            spread_atr_median=median(costs),
            spread_atr_p10=percentile(costs,.1),
            spread_atr_p90=percentile(costs,.9),
            spread_atr_pass_fraction=len(passed)/len(sample),
            spread_pass_mean_quote_markout_bps=(mean(r["quoted_markout_bps"] for r in passed)
                                                  if passed else None),
            gross_midpoint_mean_bps=(mean(r["midpoint_markout_bps"] for r in sample)),
            cost_rejected_are_descriptive_only=True,
            live_risk_authorized=False))
    ordered=sorted(groups,key=lambda g:(-g["spread_pass_count"],g["symbol"],g["side"]))
    return dict(kind="cost_feasibility_diagnostic",windows=window_counts,
        original_spread_to_m1_atr_limit=.15,
        total_observations=sum(g["observations"] for g in groups),
        total_spread_pass=sum(g["spread_pass_count"] for g in groups),
        groups=ordered,selection_permitted=False,live_execution_enabled=False,
        limitations=["Signals arose from previously examined historical prices.",
                     "Only proposal-time spread measured; broker commissions and slippage missing.",
                     "No strategy-level take-profit/stop-loss backtest or validated expectancy."])

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--report",nargs="+",required=True)
    p.add_argument("--output",required=True)
    a=p.parse_args()
    obj=profile(a.report)
    target=Path(a.output)
    if target.exists():
        raise FileExistsError("output_already_exists")
    target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text(json.dumps(obj,indent=2,allow_nan=False)+"\n",encoding="utf-8")
    print(json.dumps({k:obj[k] for k in
          ("kind","total_observations","total_spread_pass")},indent=2))
    print("Top quoted cost feasibility observations (not strategy ranking):")
    for row in obj["groups"][:12]:
        print(row["symbol"],row["side"],"spreadpass",row["spread_pass_count"],
              "/",row["observations"],"median_spread_atr",
              round(row["spread_atr_median"],3))

if __name__=="__main__":
    main()
