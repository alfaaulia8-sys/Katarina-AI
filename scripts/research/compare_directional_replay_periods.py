"""Compare two disjoint calendar-window research summaries without fitting.

This is post-hoc falsification, NOT a walk-forward model optimization.
No broker IO, historical tick path invention, or live permission.
"""
from __future__ import annotations

import argparse
from datetime import datetime,timezone
from pathlib import Path
import json


def compare_two_periods(earlier, later,*,earlier_label, later_label):
    for x in (earlier,later):
        if (x.get("live_execution_authorized") is not False or
            x.get("orders_sent")!=0 or x.get("research_action")!="WAIT" or
            x.get("backtest_is_independent_out_of_sample") is not False):
            raise ValueError("untrusted_research_only_report")
    if (set(earlier.get("symbols",())) != set(later.get("symbols",())) or
        not earlier.get("symbols") or earlier_label>=later_label):
        raise ValueError("inconsistent_symbols_or_nonchronological_periods")
    if earlier is later:
        raise ValueError("not_two_independent_period_objects")
    def keyed(report):
        out={}
        for row in report["method_side_scorecard"]:
            key=(row["method"],row["side"])
            if key in out:raise ValueError("duplicate_method_side")
            out[key]=row
        return out
    a=keyed(earlier);b=keyed(later)
    findings=[]
    for key in sorted(set(a)|set(b)):
        before=a.get(key);after=b.get(key)
        n1=before["n"] if before else 0
        n2=after["n"] if after else 0
        v1=before["mean_modeled_net_r_by_cost"]["0.15"] if before else None
        v2=after["mean_modeled_net_r_by_cost"]["0.15"] if after else None
        if not n1 or not n2:
            state="PERIOD_NOT_COMPARABLE"
        elif v1<0 and v2<0:
            state="NEGATIVE_IN_BOTH_INSPECTED_WINDOWS"
        elif v1>0 and v2>0:
            state="POSITIVE_BUT_INSPECTED_RETROSPECTIVE_WINDOWS"
        else:
            state="UNSTABLE_OR_ZERO_MEAN"
        findings.append({
            "method":key[0],"side":key[1],
            "earlier_cases":n1,"later_cases":n2,
            "earlier_mean_assumed_net_r":v1,
            "later_mean_assumed_net_r":v2,
            "verdict":state,
            "not_an_independent_out_of_sample_validation":True,
            "live_strategy_authorized":False,
        })
    return {
        "status":"TWO_HISTORICAL_PERIODS_DIRECTIONAL_FALSIFICATION",
        "calendar_windows":[earlier_label,later_label],
        "symbols":len(earlier["symbols"]),
        "historical_decisions_evaluated":(
            earlier["counters"].get("evaluated",0)+
            later["counters"].get("evaluated",0)),
        "hypothetical_ohlc_outcomes":(
            earlier["counters"].get("proxy_completed",0)+
            later["counters"].get("proxy_completed",0)),
        "conditional_virtual_admissions_across_independent_batches":(
            earlier["counters"].get("adaptive_selected",0)+
            later["counters"].get("adaptive_selected",0)),
        "strategy_side_findings":findings,
        "repeated_negative_method_sides":sum(
            x["verdict"]=="NEGATIVE_IN_BOTH_INSPECTED_WINDOWS"
            for x in findings),
        "winners_not_selected_by_posthoc_metric":True,
        "recommendation":"RESEARCH_MORE_PREDECLARED_SETUPS_AND_ASK_FOR_FRESH_TESTING",
        "production_action":"WAIT",
        "real_broker_fills_or_costs_verified":False,
        "independent_unseen_history_verified":False,
        "live_execution_authorized":False,"orders_sent":0,
    }


def main():
    p=argparse.ArgumentParser()
    p.add_argument("--earlier",required=True)
    p.add_argument("--later",required=True)
    p.add_argument("--earlier-label",required=True)
    p.add_argument("--later-label",required=True)
    p.add_argument("--output",required=True)
    x=p.parse_args()
    a=json.loads(Path(x.earlier).read_text(encoding="utf-8"))
    b=json.loads(Path(x.later).read_text(encoding="utf-8"))
    result=compare_two_periods(a,b,earlier_label=x.earlier_label,later_label=x.later_label)
    result["assessed_utc"]=datetime.now(timezone.utc).isoformat()
    file=Path(x.output);file.parent.mkdir(parents=True,exist_ok=True)
    tmp=file.with_suffix(".tmp")
    tmp.write_text(json.dumps(result,indent=2,allow_nan=False)+"\n",encoding="utf-8")
    tmp.replace(file)
    print("KATARINA_TWO_PERIOD_DIRECTIONAL_VERDICT",json.dumps({
        "symbols":result["symbols"],
        "evaluated":result["historical_decisions_evaluated"],
        "ohlc_outcomes":result["hypothetical_ohlc_outcomes"],
        "negative_in_both":result["repeated_negative_method_sides"],
        "compared":len(result["strategy_side_findings"]),
        "orders":0,"live":False,
    }))


if __name__=="__main__":main()
