"""Combine disjoint MT5 historical Brain batches without inventing portfolio P&L.

Input: 3–6 PRIVATE broker spread snapshot replay JSONs. No network,
no broker API, no parameter tuning. Strict double-counting checks.
Only mathematically valid weighted mean modeled R is aggregated;
batch-specific profit factors, equity paths, and drawdowns CANNOT be
merged by averaging their ratios. All signs, losers and WAITs included.
"""
from __future__ import annotations

import argparse
from collections import defaultdict,Counter
from datetime import datetime,timezone
from pathlib import Path
import json
from math import isfinite

COST_LEVELS=("0.05","0.15","0.3")


def aggregate_batches(reports:list[dict])->dict:
    if not 1<=len(reports)<=8:
        raise ValueError("bounded_broker_replay_batch_count_required")
    symbols=set()
    totals=Counter()
    side=defaultdict(lambda:{"candidates":0,"weighted_sums":defaultdict(float),
                             "cohorts":0,"symbols":set()})
    market=defaultdict(lambda:{"candidates":0,"weighted_net_r":0.0})
    per_group=[]
    for report in reports:
        if (report.get("live_execution_authorized") is not False or
            report.get("orders_sent") != 0 or
            report.get("read_only") is not True or
            report.get("spread_source")!="BROKER_M5_CLOSED_BAR_SPREAD_POINTS" or
            report.get("actual_historical_entry_bidask_verified") is not False or
            report.get("retrospective_data_already_inspected_not_independent_holdout") is not True):
            raise ValueError("untrusted_broker_replay_evidence_provenance")
        names=report.get("symbols_requested",())
        if not names or len(set(names))!=len(names) or symbols.intersection(names):
            raise ValueError("duplicate_or_missing_batch_symbols")
        symbols.update(names)
        for k,v in report["counters"].items():
            if isinstance(v,int):totals[k]+=v
        splits=report["purged_calendar_split_counts"]
        for stage in ("train","validation","test","purged_or_embargoed"):
            totals["split_"+stage]+=splits.get(stage,0)
        adaptive=report.get("adapted_replay",{}).get("adaptive",{})
        totals["adaptive_selected"]+=adaptive.get("trades",0) or 0
        totals["adaptive_wait"]+=adaptive.get("wait_events",0) or 0
        costs=report["full_cost_sensitivity"]
        for c in costs["cohorts"]:
            n=c.get("all_attempts_including_blocked",0)
            if not isinstance(n,int) or n<1 or c["symbol"] not in names:
                raise ValueError("untrusted_method_cohort")
            key=(c["method"],c["side"])
            item=side[key]
            item["candidates"]+=n
            item["cohorts"]+=1
            item["symbols"].add(c["symbol"])
            px=market[c["symbol"]]
            px["candidates"]+=n
            price=c.get("cost_scenarios_r",{})
            for cost in COST_LEVELS:
                scenario=price.get(cost)
                if not scenario:
                    raise ValueError("missing_frozen_cost_sensitivity")
                v=scenario.get("mean_net_proxy_r")
                if not isinstance(v,(int,float)) or not isfinite(v):
                    raise ValueError("nonfinite_cost_stressed_replay")
                item["weighted_sums"][cost]+=v*n
            px["weighted_net_r"]+=price["0.15"]["mean_net_proxy_r"]*n
        totals["labelled_candidates_in_cost_review"]+=costs["candidate_total"]
        per_group.append({
            "symbols":list(names),
            "simulated_paper_selected":adaptive.get("trades",0) or 0,
            "simulated_paper_wait":adaptive.get("wait_events",0) or 0,
            "batch_specific_expectancy_r":adaptive.get("expectancy_r"),
            "cannot_combine_independent_batch_equity_as_one_portfolio":True,
        })
    if totals["labelled_candidates_in_cost_review"]!=totals["proxy_completed"]:
        raise ValueError("cohort_sample_count_does_not_match_simulation")
    if sum(x["candidates"] for x in side.values())!=totals["proxy_completed"]:
        raise ValueError("cost_cohort_sample_denominator_mismatch")
    cohorts=[{
        "method":method,"side":direction,
        "n":v["candidates"],"symbols":sorted(v["symbols"]),
        "mean_modeled_net_r_by_cost":{
            cost:round(v["weighted_sums"][cost]/v["candidates"],6)
            for cost in COST_LEVELS},
        "cross_symbol_robustness_unproven":True,
        "may_authorize_live":False,
    } for (method,direction),v in sorted(side.items())]
    per_symbol=[{
        "symbol":symbol,"n":v["candidates"],
        "mean_modeled_net_r_at_0_15r":round(
            v["weighted_net_r"]/v["candidates"],6) if v["candidates"] else None,
        "is_actual_broker_net_performance":False,
    } for symbol,v in sorted(market.items())]
    return {
        "status":"RESEARCH_ONLY_MULTI_SYMBOL_REPLAY_AGGREGATED",
        "symbols":sorted(symbols),"symbol_count":len(symbols),
        "batch_count":len(reports),
        "counters":dict(totals),
        "method_side_scorecard":cohorts,
        "symbol_scorecard":per_symbol,
        "independent_batch_research":per_group,
        "source":"BROKER_CLOSED_M5_SPREAD_WITH_UNEXECUTED_OHLC_PROXY",
        "actual_tick_bidask_entries_and_fills_verified":False,
        "true_broker_cost_schedule_verified":False,
        "backtest_is_independent_out_of_sample":False,
        "true_17_symbol_combined_portfolio_PF_or_drawdown_available":False,
        "profitability_not_demonstrated":True,
        "repeated_parameter_fitting_permitted":False,
        "research_action":"WAIT",
        "live_execution_authorized":False,
        "orders_sent":0,
    }


def main():
    p=argparse.ArgumentParser()
    p.add_argument("--inputs",nargs="+",required=True)
    p.add_argument("--output",required=True)
    a=p.parse_args()
    if len(a.inputs)>8:p.error("maximum 8 broker-private input files")
    reports=[json.loads(Path(name).read_text(encoding="utf-8")) for name in a.inputs]
    result=aggregate_batches(reports)
    result["aggregated_at_utc"]=datetime.now(timezone.utc).isoformat()
    path=Path(a.output);path.parent.mkdir(parents=True,exist_ok=True)
    tmp=path.with_suffix(".tmp")
    tmp.write_text(json.dumps(result,indent=2,allow_nan=False)+"\n",encoding="utf-8")
    tmp.replace(path)
    print("KATARINA_DIRECTIONAL_REPLAY_AGGREGATE",json.dumps({
        "symbols":result["symbol_count"],
        "historical_cuts":result["counters"].get("evaluated",0),
        "outcomes":result["counters"].get("proxy_completed",0),
        "adaptive_selected":result["counters"].get("adaptive_selected",0),
        "methods":result["method_side_scorecard"],
        "live":False,"orders":0
    },allow_nan=False),flush=True)


if __name__=="__main__":
    main()
