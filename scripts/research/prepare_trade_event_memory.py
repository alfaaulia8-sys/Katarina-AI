"""Prepare symbol-specific TP-before-SL examples for future meta-labeling.

Uses ONLY already-audited quote paths. Different symbols retain
different stops/targets. No model fit, no automation to trade, no
probability-of-win claims. Chronological labels must have resolved.
"""
from __future__ import annotations
import argparse,json
from collections import defaultdict,Counter
from datetime import datetime,timezone
from hashlib import sha256
from pathlib import Path
from bisect import bisect_right
from statistics import mean

UTC=timezone.utc
CUTOFF="2026-10-10T12:00:00+00:00"
KNOWN={
"NAS100.vx":("original","nas_trend_pullback_continuation_v1"),
"XAUUSD.vx":("alternatives","gold_sweep_rejection_30m_structural_v2"),
"US30.vx":("alternatives","dow_newyork_failed_break_mean_revert_v2"),
"JPN225.vx":("alternatives","nikkei_tokyo_open_range_impulse_v2")}

def timestamp(x):
    dt=datetime.fromisoformat(x)
    if dt.tzinfo is None:raise ValueError("missing_utc_offset")
    return dt.timestamp()

def generate(archives,regime):
    before=timestamp(CUTOFF)
    index=defaultdict(list)
    for event in regime["classified_observations"]:
        index[event["symbol"]].append((timestamp(event["close_time_utc"]),event["regime"]))
    for name in index:index[name].sort()
    events=defaultdict(list);seen=set()
    for doc in archives:
        if doc.get("kind")!="distinct_per_symbol_research_playbooks_v1" or doc.get("live_execution_enabled") is not False:
            raise ValueError("untrusted_broker_backtest")
        arm=doc.get("research_playbook_arm","original")
        for x in doc["trials"]:
            s=x["symbol"]
            if s not in KNOWN or (arm,x["family"])!=KNOWN[s] or x["slippage_each_side_ticks"]!=1:
                continue
            key=(s,x["entry_signal_close_utc"])
            if key in seen:raise ValueError("overlap_between_broker_files")
            seen.add(key)
            if x["status"]!="CLOSED":continue
            signal=timestamp(x["entry_signal_close_utc"])
            exit_time=timestamp(x["close_time_utc"])
            if not signal<exit_time+1e-5 or exit_time+4*3600>=before:
                continue
            if x["exit_reason"] not in ("TP","SL","TIME"):
                raise ValueError("unrecognized_tick_exit_type")
            sample=index[s]
            j=bisect_right([z[0] for z in sample],signal)-1
            if j>=0 and 0<=signal-sample[j][0]<=1800:
                regime_state=sample[j][1]
                regime_time=datetime.fromtimestamp(sample[j][0],UTC).isoformat()
            else:
                regime_state="UNAVAILABLE";regime_time=None
            events[s].append(dict(
                symbol=s,family=x["family"],signal_utc=x["entry_signal_close_utc"],
                event_exit_utc=x["close_time_utc"],research_period=x["research_window"],
                side=x["side"],historical_regime=regime_state,
                regime_observation_utc=regime_time,
                ATR_at_signal=x["signal_atr"],
                entry_spread_over_ATR=x["entry_spread_div_atr"],
                actual_replay_exit_type=x["exit_reason"],
                tp_first=int(x["exit_reason"]=="TP"),
                positive_hypothetical_R=int(x["R"]>0),
                simulated_net_R=x["R"],
                cost_assumption="real_bid_ask_plus_one_adverse_tick_each_side",
                filled_real_order=False))
    buckets={}
    for sym,(arm,family) in KNOWN.items():
        rows=sorted(events[sym],key=lambda x:x["signal_utc"])
        values=[x["simulated_net_R"] for x in rows]
        counts=Counter(x["actual_replay_exit_type"] for x in rows)
        buckets[sym]=dict(family=family,arm=arm,
            events=len(rows),by_exit_reason=dict(counts),
            average_R=mean(values) if values else None,
            distinct_days=len(set(x["signal_utc"][:10] for x in rows)),
            sufficient_for_meta_model=len(rows)>=100 and (
                len(set(x["signal_utc"][:10] for x in rows))>=20),
            chronological_samples=rows,
            model_promotion_allowed=False)
    return dict(kind="historical_per_symbol_tp_before_sl_event_memory_v1",
       frozen_before_utc=CUTOFF,
       raw_context_looks_back_only=True,
       labels_resolved_before_memory_freeze=True,
       not_an_untouched_out_of_sample_test=True,
       target_is_broker_quote_replayed_first_barrier_not_future_close_direction=True,
       no_real_broker_deals=True,
       market_regime_context_is_research_only=True,
       model_training_allowed_only_on_earlier_data=True,
       model_promotion_allowed=False,live_execution_enabled=False,
       by_symbol=buckets,decision="NO_TRADE")

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--reports",nargs="+",required=True)
    p.add_argument("--regime",required=True)
    p.add_argument("--output",required=True)
    a=p.parse_args()
    target=Path(a.output)
    if target.exists():raise FileExistsError("never_overwrite_event_memory")
    artifacts=[Path(p).read_bytes() for p in a.reports]
    regime=Path(a.regime).read_bytes()
    doc=generate(list(map(json.loads,artifacts)),json.loads(regime))
    doc["source_hashes"]=dict(
         strategies=[sha256(raw).hexdigest() for raw in artifacts],
         regime=sha256(regime).hexdigest())
    target.write_text(json.dumps(doc,indent=2,allow_nan=False)+"\n",encoding="utf-8")
    print(json.dumps({s:dict(events=r["events"],exit=r["by_exit_reason"],
              mean_R=r["average_R"],sample_sufficient=r["sufficient_for_meta_model"])
              for s,r in doc["by_symbol"].items()},indent=2))
    print("OUTPUT",target)
if __name__=="__main__":
    main()
