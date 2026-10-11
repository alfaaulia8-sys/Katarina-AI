"""Exploratory session/regime check on *existing* broker-executed quote trials.

Not independent. Fixed six hypothesis filters; no optimization based on
later-period data; no promotion. Broker order simulator remains unchanged.
"""
from __future__ import annotations
from collections import defaultdict
from datetime import datetime
import argparse,json
from pathlib import Path
from statistics import mean,stdev
from math import sqrt
from hashlib import sha256

FILTERS={
 "unfiltered":lambda s:True,
 "london_newyork":lambda s:7<=datetime.fromisoformat(s["signal_close_utc"]).hour<18,
 "london_trend_active":lambda s:(7<=datetime.fromisoformat(s["signal_close_utc"]).hour<12
      and s["context_adx"]>=25 and s["volume_ratio"]>=1.25),
 "newyork_trend_active":lambda s:(12<=datetime.fromisoformat(s["signal_close_utc"]).hour<18
      and s["context_adx"]>=25 and s["volume_ratio"]>=1.25),
 "sweep_range_active":lambda s:(7<=datetime.fromisoformat(s["signal_close_utc"]).hour<18
      and s["context_adx"]<=20 and s["volume_ratio"]>=1.1),
 "all_hours_strong_volume":lambda s:s["volume_ratio"]>=1.5,
}

def stats(samples):
    s=[x for x in samples if x["status"]=="CLOSED" and x["R"] is not None]
    days=defaultdict(list)
    for x in s:
        days[x["signal_close_utc"][:10]].append(x["R"])
    daily=[mean(group) for group in days.values()]
    a=[x["R"] for x in s]
    good=sum(v for v in a if v>0)
    bad=-sum(v for v in a if v<0)
    return dict(n=len(a),dates=len(days),mean_r=mean(a) if a else None,
        profit_factor=good/bad if bad else None,
        lower99pct_daily_r=(mean(daily)-2.576*stdev(daily)/sqrt(len(daily))
              if len(daily)>=2 else None),
        diagnostic_only=True)

def examine(doc):
    if doc.get("report_version")!="broker_aware_independent_strategy_tick_study_v1":
        raise ValueError("invalid_broker_tick_report")
    if doc.get("live_execution_enabled") is not False:
        raise ValueError("live_not_disabled")
    study=[e for e in doc["trials"]
           if e["adverse_slippage_each_side_ticks"]==1
           and e["tp_atr"]==2. and e["sl_atr"]==1.]
    keys=sorted({(e["symbol"],e["family"],e["side"]) for e in study})
    data=[]
    for k in keys:
        for name,filter_ in FILTERS.items():
            parts={}
            for period in ("development_aug","development_sep","diagnostic_oct"):
                arr=[x for x in study if (x["symbol"],x["family"],x["side"])==k
                     and x["phase"]==period and filter_(x)]
                parts[period]=stats(arr)
            enough=all(parts[w]["n"]>=15 and parts[w]["dates"]>=6
                       for w in ("development_aug","development_sep"))
            stable=enough and all(
                parts[w]["mean_r"] is not None and parts[w]["mean_r"]>0
                and parts[w]["lower99pct_daily_r"] is not None
                and parts[w]["lower99pct_daily_r"]>0
                and parts[w]["profit_factor"] is not None
                and parts[w]["profit_factor"]>=1.2
                for w in ("development_aug","development_sep"))
            data.append(dict(symbol=k[0],family=k[1],side=k[2],filter=name,
                sufficient_development=enough,strict_positive_development=stable,
                phase_results=parts,model_promotion_allowed=False))
    return dict(kind="post_hoc_session_and_regime_diagnostic",
        filter_count=len(FILTERS),per_family_side_cases=len(data),
        historically_observed_price_fitted_before_analysis=True,
        october_not_pristine_holdout=True,
        positive_development_cases=[r for r in data if r["strict_positive_development"]],
        all_cases=data,research_only=True,
        live_execution_enabled=False,model_promotion_allowed=False)

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--report",required=True)
    p.add_argument("--output",required=True)
    a=p.parse_args()
    output=Path(a.output)
    if output.exists():raise FileExistsError("no_research_file_overwrite")
    raw=Path(a.report).read_bytes()
    data=examine(json.loads(raw))
    data["source_sha256"]=sha256(raw).hexdigest()
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(data,indent=2,allow_nan=False)+"\n")
    print("FILTER_CASES",data["per_family_side_cases"],
        "POSITIVE_BOTH_DEVELOPMENT_WITH_CONFIDENCE",
        len(data["positive_development_cases"]))
    for item in data["positive_development_cases"][:12]:
        print(item["symbol"],item["family"],item["side"],item["filter"],
            item["phase_results"])
if __name__=="__main__":
    main()
