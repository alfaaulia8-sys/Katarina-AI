"""Merge disjoint authorized-broker research batches without reshaping trials."""
from __future__ import annotations
import argparse,json
from hashlib import sha256
from pathlib import Path

REQUIRED_KIND="broker_aware_independent_strategy_tick_study_v1"

def merge(paths):
    docs=[]
    names=set()
    for path in paths:
        raw=Path(path).read_bytes()
        result=json.loads(raw)
        if result.get("report_version")!=REQUIRED_KIND or (
           result.get("live_execution_enabled") is not False or
           result.get("model_promotion_allowed") is not False):
            raise ValueError("unexpected_source_or_live_risk")
        source_symbols=set(result["symbol_scope"])
        if source_symbols&names:
            raise ValueError("duplicate_broker_symbol")
        if len(source_symbols)!=len(result["symbol_scope"]):
            raise ValueError("duplicate_symbols_in_batch")
        if len(result["trials"])!=result["result_count"]:
            raise ValueError("wrong_trial_count")
        names|=source_symbols
        docs.append((result,dict(input_path=str(path),
             sha256=sha256(raw).hexdigest(),
             source_symbols=sorted(source_symbols),
             entry_scenarios=result["result_count"])))
    one=docs[0][0]
    must_match=("date_windows_utc","decision_latency_seconds",
        "maximum_quote_wait_seconds","max_historical_spread_atr",
        "adverse_slippage_each_side_ticks","hypothetical_exit_grid",
        "hold_seconds")
    for item,manifest in docs[1:]:
        if any(item.get(key)!=one.get(key) for key in must_match):
            raise ValueError("inconsistent_backtest_rules")
        if item.get("broker")!=one.get("broker"):
            raise ValueError("inconsistent_account_broker_model")
    output=dict(one)
    output["symbol_scope"]=sorted(names)
    output["trials"]=[t for doc,manifest in docs for t in doc["trials"]]
    output["summaries"]=[s for doc,manifest in docs for s in doc["summaries"]]
    output["per_scan"]={k:v for doc,manifest in docs for k,v in doc["per_scan"].items()}
    output["result_count"]=len(output["trials"])
    output["source_batches"]=[manifest for doc,manifest in docs]
    output["report_version"]=REQUIRED_KIND
    output["merge_is_read_only"]=True
    output["no_trading_validation_claim"]=True
    output["live_execution_enabled"]=False
    output["model_promotion_allowed"]=False
    return output

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--input",nargs="+",required=True)
    p.add_argument("--output",required=True)
    a=p.parse_args()
    out=Path(a.output)
    if out.exists():raise FileExistsError("never_overwrite_merged_report")
    merged=merge(a.input)
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(merged,indent=2,allow_nan=False)+"\n",encoding="utf-8")
    print(json.dumps(dict(symbols=merged["symbol_scope"],
              scenario_rows=merged["result_count"],source_batches=len(merged["source_batches"]),
              output=str(out))))
if __name__=="__main__":
    main()
