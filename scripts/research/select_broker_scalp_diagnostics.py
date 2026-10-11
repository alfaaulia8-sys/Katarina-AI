"""Select diagnostics chronologically from development, then evaluate later.

Never optimize against October. October was previously inspected by
KATARINA and is NOT an untouched holdout; no live model promotion.
"""
from __future__ import annotations
from collections import defaultdict
from hashlib import sha256
from math import sqrt
from pathlib import Path
from statistics import mean,stdev
import argparse,json

MIN_TRAIN_PER_WINDOW=20
MIN_DAYS_PER_WINDOW=8
MIN_RESEARCH_PF=1.10
MIN_TOTAL_TRAIN=50
SCORE_SLIPPAGE_TICKS=1

def summary(rows):
    clean=[x for x in rows if x["status"]=="CLOSED" and x["R"] is not None]
    days=defaultdict(list)
    for event in clean:
        days[event["signal_close_utc"][:10]].append(event["R"])
    if not clean:
        return dict(n=0,n_all=len(rows),days=0,mean_r=None,profit_factor=None,
                    lower_99pct_day_r=None,win_fraction=None,
                    max_drawdown_r=None,usd_minlot_sum=None)
    vals=[float(e["R"]) for e in clean]
    positive=sum(x for x in vals if x>0)
    negative=-sum(x for x in vals if x<0)
    daily=[mean(v) for d,v in sorted(days.items())]
    lower=(mean(daily)-2.576*stdev(daily)/sqrt(len(daily))
           if len(daily)>=2 else None)
    risk=peak=draw=0
    for event in sorted(clean,key=lambda e:e["entry_time_utc"]):
        risk+=event["R"]
        peak=max(peak,risk)
        draw=max(draw,peak-risk)
    usd=[e["usd_minlot"] for e in clean]
    return dict(n=len(clean),n_all=len(rows),days=len(days),
      mean_r=mean(vals),profit_factor=positive/negative if negative else None,
      lower_99pct_day_r=lower,
      win_fraction=sum(x>0 for x in vals)/len(vals),
      max_drawdown_r=draw,
      usd_minlot_sum=sum(usd) if all(v is not None for v in usd) else None)

def compare(report):
    if report.get("report_version")!="broker_aware_independent_strategy_tick_study_v1":
        raise ValueError("wrong_input")
    if report.get("live_execution_enabled") is not False or (
          report.get("model_promotion_allowed") is not False):
        raise ValueError("live_flag")
    rec=report["trials"]
    if len(rec)!=report["result_count"]:
        raise ValueError("invalid_trial_count")
    group=defaultdict(list)
    for event in rec:
        if event.get("trade_filled") is not False or event.get("strategy_live_authorized") is not False:
            raise ValueError("wrong_risk_flag")
        key=(event["symbol"],event["family"],event["side"],
             event["tp_atr"],event["sl_atr"],event["adverse_slippage_each_side_ticks"])
        group[(key,event["phase"])].append(event)
    possible=sorted({key for key,_ in group if key[5]==SCORE_SLIPPAGE_TICKS})
    comparison=[]
    for key in possible:
        aug=summary(group[(key,"development_aug")])
        sep=summary(group[(key,"development_sep")])
        octo=summary(group[(key,"diagnostic_oct")])
        enough=(aug["n"]>=MIN_TRAIN_PER_WINDOW and aug["days"]>=MIN_DAYS_PER_WINDOW
              and sep["n"]>=MIN_TRAIN_PER_WINDOW and sep["days"]>=MIN_DAYS_PER_WINDOW
              and aug["n"]+sep["n"]>=MIN_TOTAL_TRAIN)
        aug_positive=(aug["mean_r"] is not None and aug["mean_r"]>0)
        sep_positive=(sep["mean_r"] is not None and sep["mean_r"]>0)
        broad_pf=all(x["profit_factor"] is not None and
                   x["profit_factor"]>=MIN_RESEARCH_PF for x in (aug,sep))
        confidence_ok=all(x["lower_99pct_day_r"] is not None and
                          x["lower_99pct_day_r"]>0 for x in (aug,sep))
        dev_pass=all((enough,aug_positive,sep_positive,broad_pf,confidence_ok))
        ranking=min(aug["mean_r"],sep["mean_r"]) if (
                 aug["mean_r"] is not None and sep["mean_r"] is not None) else -999
        comparison.append(dict(symbol=key[0],family=key[1],side=key[2],
           tp_atr=key[3],sl_atr=key[4],adverse_slippage_each_side_ticks=key[5],
           development_aug=aug,development_sep=sep,
           chronological_october_diagnostic=octo,
           selection_sample_sufficient=enough,
           development_pass=dev_pass,
           diagnostic_score_worst_development_mean_r=ranking,
           model_promotion_allowed=False))
    # Selection order is determined solely by development data.
    # Sufficient evidence precedes tiny, chance-positive sets so the
    # shortlist cannot be dominated by a handful of lucky trades.
    ordered=sorted(comparison,key=lambda x:(
        -int(x["development_pass"]),
        -int(x["selection_sample_sufficient"]),
        -x["diagnostic_score_worst_development_mean_r"],
        x["symbol"],x["family"],x["side"],x["tp_atr"],x["sl_atr"]))
    return dict(report_kind="multi_setup_broker_aware_diagnostic_selection",
       candidate_combinations_considered=len(ordered),
       criterion="predeclared positive development Aug and Sep, >=20 trades >=8 days each, PF>=1.1 each, 99% daily mean lower bound >0",
       selected_according_to_older_periods=ordered[:10],
       all_combinations=ordered,
       has_development_pass=any(x["development_pass"] for x in ordered),
       october_is_previous_researched_not_untouched_holdout=True,
       strategy_validated=False,model_promotion_allowed=False,
       live_execution_enabled=False,decision="NO_TRADE")

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--report",required=True)
    p.add_argument("--output",required=True)
    args=p.parse_args()
    path=Path(args.output)
    if path.exists():
        raise FileExistsError("immutable_selection_already_exists")
    bytes_=Path(args.report).read_bytes()
    study=json.loads(bytes_)
    response=compare(study)
    response["input_sha256"]=sha256(bytes_).hexdigest()
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(response,indent=2,allow_nan=False)+"\n",encoding="utf-8")
    print("CANDIDATES",len(response["all_combinations"]),
          "PASS",response["has_development_pass"])
    for row in response["selected_according_to_older_periods"][:10]:
        print(json.dumps(dict(symbol=row["symbol"],family=row["family"],
             side=row["side"],tp=row["tp_atr"],sl=row["sl_atr"],
             aug=row["development_aug"],sep=row["development_sep"],
             oct=row["chronological_october_diagnostic"],
             development_pass=row["development_pass"])),flush=True)
    print("OUTPUT "+str(path))
if __name__=="__main__":
    main()
