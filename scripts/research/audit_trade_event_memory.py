"""Recalculate broker-quote TP-first example bank and reject future labels."""
import argparse,json
from datetime import datetime
from hashlib import sha256
from pathlib import Path
from prepare_trade_event_memory import generate

def audit(memory,source,regime):
    if memory.get("kind")!="historical_per_symbol_tp_before_sl_event_memory_v1" or (
      memory.get("live_execution_enabled") is not False or
      memory.get("model_promotion_allowed") is not False):
        raise ValueError("unsafe_event_memory_archive")
    recomputed=generate(source,regime)
    for key in ("by_symbol","target_is_broker_quote_replayed_first_barrier_not_future_close_direction",
                "frozen_before_utc"):
        if memory.get(key)!=recomputed.get(key):
            raise ValueError("market_event_data_changed_"+key)
    frozen=datetime.fromisoformat(memory["frozen_before_utc"]).timestamp()
    count=0
    for sym,pack in memory["by_symbol"].items():
        for e in pack["chronological_samples"]:
            t=datetime.fromisoformat(e["signal_utc"]).timestamp()
            exit_time=datetime.fromisoformat(e["event_exit_utc"]).timestamp()
            if not t<=exit_time< frozen-4*3600:
                raise ValueError("unresolved_event_label")
            if e.get("filled_real_order") is not False:
                raise ValueError("fictional_real_trade")
            if e["tp_first"]!=int(e["actual_replay_exit_type"]=="TP"):
                raise ValueError("wrong_tp_first_target")
            count+=1
    return dict(kind="symbol_specific_first_barrier_memory_audit",
        entries_checked=count,market_count=len(memory["by_symbol"]),
        chronological_outcome_validation_passed=True,
        quote_replay_exit_reason_matched=True,
        no_promoted_trading_signal=True,
        model_promotion_allowed=False,live_execution_enabled=False)

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--memory",required=True)
    p.add_argument("--reports",nargs="+",required=True)
    p.add_argument("--regime",required=True)
    p.add_argument("--output",required=True)
    a=p.parse_args()
    raw=Path(a.memory).read_bytes()
    m=json.loads(raw)
    strategy=[Path(x).read_bytes() for x in a.reports]
    regime=Path(a.regime).read_bytes()
    hashes=m.get("source_hashes",{})
    if hashes.get("strategies")!=[sha256(t).hexdigest() for t in strategy] or (
          hashes.get("regime")!=sha256(regime).hexdigest()):
        raise ValueError("source_provenance_failure")
    result=audit(m,list(map(json.loads,strategy)),json.loads(regime))
    result["archive_sha256"]=sha256(raw).hexdigest()
    dest=Path(a.output)
    if dest.exists():raise FileExistsError("immutable")
    dest.write_text(json.dumps(result,indent=2)+"\n")
    print(json.dumps(result,indent=2))
if __name__=="__main__":
    main()
