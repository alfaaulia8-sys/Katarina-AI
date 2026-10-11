"""Does a *frozen* regime gate help existing per-symbol broker-tick setups?

Strategy outcomes already include historical bid/ask and +1 adverse
tick each side; joins require previously observable regime at/before
entry and within 30min. No feature fitting or post-hoc gate selection.
This is reused retrospective evidence, not prospective OOS.
"""
from __future__ import annotations
from bisect import bisect_right
from collections import Counter,defaultdict
from datetime import datetime,timezone
from hashlib import sha256
from pathlib import Path
from statistics import mean
import argparse,json
UTC=timezone.utc
MAX_AGE_SECONDS=1800.
MIN_SELECTED=30
MIN_DAYS=10

CONTRACT={
    "NAS100.vx":dict(arm="original",family="nas_trend_pullback_continuation_v1",
      gate="trend_or_pullback_same_direction"),
    "XAUUSD.vx":dict(arm="alternatives",family="gold_sweep_rejection_30m_structural_v2",
      gate="sideways_or_confirmed_reversal"),
    "US30.vx":dict(arm="alternatives",family="dow_newyork_failed_break_mean_revert_v2",
      gate="sideways_or_confirmed_reversal"),
    "JPN225.vx":dict(arm="alternatives",family="nikkei_tokyo_open_range_impulse_v2",
      gate="confirmed_aligned_continuation"),
}

def seconds(iso):
    d=datetime.fromisoformat(iso)
    if d.tzinfo is None:raise ValueError("naive_time")
    return d.timestamp()

def gate(symbol,side,state):
    suf="UP" if side=="BUY" else "DOWN"
    direction=state.endswith("_"+suf)
    contract=CONTRACT[symbol]["gate"]
    if contract=="trend_or_pullback_same_direction":
        return direction and (state.startswith("CONTINUATION_") or
            state.startswith("LOCAL_CONTINUATION_") or
            state.startswith("PULLBACK_"))
    if contract=="sideways_or_confirmed_reversal":
        return state=="SIDEWAYS" or state=="REVERSAL_"+suf
    if contract=="confirmed_aligned_continuation":
        return direction and (state.startswith("CONTINUATION_") or
            state.startswith("LOCAL_CONTINUATION_"))
    raise ValueError("unregistered_gate_kind")

def metric(values):
    if not values:return dict(n=0,mean_R=None,profit_factor=None,
                              distinct_dates=0,percent_R_positive=None)
    results=[x["R"] for x in values]
    positive=sum(x for x in results if x>0)
    negative=-sum(x for x in results if x<0)
    return dict(n=len(values),mean_R=mean(results),
        profit_factor=positive/negative if negative else None,
        distinct_dates=len({x["entry_signal_close_utc"][:10] for x in values}),
        percent_R_positive=sum(x>0 for x in results)/len(results))

def evaluate(regime,raw_sources):
    if regime.get("kind")!="causal_mtf_market_regime_diagnostics_v1":
        raise ValueError("invalid_regime_archive")
    if regime.get("live_execution_enabled") is not False:
        raise ValueError("dangerous_archive")
    index=defaultdict(list)
    for e in regime["classified_observations"]:
        index[e["symbol"]].append((seconds(e["close_time_utc"]),e["regime"]))
    for symbol in index:
        index[symbol].sort()
    compiled=[]
    checked=set()
    for source in raw_sources:
        document=source["document"]
        if document.get("kind")!="distinct_per_symbol_research_playbooks_v1" or (
             document.get("live_execution_enabled") is not False):
            raise ValueError("unsafe_strategy_outcomes")
        for row in document["trials"]:
            symbol=row["symbol"]
            if symbol not in CONTRACT or (
                 row["family"]!=CONTRACT[symbol]["family"] or
                 document.get("research_playbook_arm","original")!=CONTRACT[symbol]["arm"] or
                 row["slippage_each_side_ticks"]!=1):
                continue
            t=seconds(row["entry_signal_close_utc"])
            unique=(symbol,row["research_window"],t,row["family"])
            if unique in checked:raise ValueError("duplicate_trade")
            checked.add(unique)
            if row["status"]!="CLOSED":continue
            observations=index[symbol]
            clocks=[x[0] for x in observations]
            j=bisect_right(clocks,t)-1
            if j<0 or t-clocks[j]>MAX_AGE_SECONDS:
                state="UNAVAILABLE"
                reason="regime_missing_or_too_old"
            else:
                state=observations[j][1]
                reason="asof"
            accepted=(state!="UNKNOWN" and state!="UNAVAILABLE" and
                      gate(symbol,row["side"],state))
            compiled.append(dict(symbol=symbol,period=row["research_window"],
                family=row["family"],side=row["side"],
                entry_signal_close_utc=row["entry_signal_close_utc"],
                regime_observation_utc=(datetime.fromtimestamp(clocks[j],UTC).isoformat()
                  if reason=="asof" else None),
                regime_clock_age_seconds=t-clocks[j] if reason=="asof" else None,
                regime_state=state,gate_pass=accepted,
                R=row["R"],slippage_each_side_ticks=1,
                no_real_trade_executed=True,predeclared_gate_contract=CONTRACT[symbol]["gate"]))
    summary=[]
    for sym in CONTRACT:
        s=[x for x in compiled if x["symbol"]==sym]
        if not s:continue
        for phase in sorted({x["period"] for x in s}):
            curr=[x for x in s if x["period"]==phase]
            eligible=[x for x in curr if x["gate_pass"]]
            observed=[x for x in curr if x["regime_state"]!="UNAVAILABLE"]
            summary.append(dict(symbol=sym,period=phase,
                original_all=metric(curr),regime_gated=metric(eligible),
                gate_selected_fraction=len(eligible)/len(curr) if curr else None,
                aligned_regime_count=len(observed),
                matched_state_distribution=dict(Counter(x["regime_state"] for x in curr)),
                adequate_gated_sample=(len(eligible)>=MIN_SELECTED and
                    len({x["entry_signal_close_utc"][:10] for x in eligible})>=MIN_DAYS),
                broker_quote_net_research_not_actual_cash_PnL=True,
                model_promotion_allowed=False))
    bysym=[]
    for sym in CONTRACT:
        s=[x for x in compiled if x["symbol"]==sym]
        if not s:continue
        eligible=[x for x in s if x["gate_pass"]]
        bysym.append(dict(symbol=sym,all=metric(s),gated=metric(eligible),
            selected_fraction=len(eligible)/len(s) if s else None,
            sample_sufficient=(len(eligible)>=MIN_SELECTED and
                len({x["entry_signal_close_utc"][:10] for x in eligible})>=MIN_DAYS),
            promoted=False))
    return dict(kind="market_regime_predeclared_gate_trade_diagnostic_v1",
       market_regime_engine_version=regime["engine_version"],
       handpicked_post_hoc_research_caveat=True,
       price_outcome_from_earlier_broker_tick_replays=True,
       already_used_history_not_true_unseen_OOS=True,
       gates_predeclared_before_computing_this_study=True,
       full_lookahead_guard_age_seconds=MAX_AGE_SECONDS,
       strategy_specific_gate=CONTRACT,
       symbols=sorted(CONTRACT),
       all_trades_scenarios=len(compiled),
       per_symbol=bysym,per_symbol_period=summary,
       matched_trials=compiled,
       model_promotion_allowed=False,live_execution_enabled=False,
       decision="NO_TRADE")

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--regime",required=True)
    p.add_argument("--strategies",nargs="+",required=True)
    p.add_argument("--output",required=True)
    a=p.parse_args()
    out=Path(a.output)
    if out.exists():raise FileExistsError("immutable")
    data=Path(a.regime).read_bytes()
    refs=[]
    docs=[]
    for file in a.strategies:
        raw=Path(file).read_bytes()
        refs.append(dict(file=str(file),sha256=sha256(raw).hexdigest()))
        docs.append(dict(document=json.loads(raw)))
    result=evaluate(json.loads(data),docs)
    result["source_sha256"]=dict(regime=sha256(data).hexdigest(),strategies=refs)
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(result,indent=2,allow_nan=False)+"\n",encoding="utf-8")
    print("BY_SYMBOL")
    for item in result["per_symbol"]:
        print(json.dumps(item),flush=True)
    print("BY_WINDOW")
    for item in result["per_symbol_period"]:
        print(json.dumps(dict(symbol=item["symbol"],window=item["period"],
             all=item["original_all"],gate=item["regime_gated"],
             sampled=item["adequate_gated_sample"])),flush=True)
    print("OUTPUT",out)
if __name__=="__main__":
    main()
