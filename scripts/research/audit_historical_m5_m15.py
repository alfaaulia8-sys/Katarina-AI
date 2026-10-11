"""Auditable causal chronology for independent historical M5/M15 trials."""
from __future__ import annotations
import argparse,json,re
from datetime import datetime
from hashlib import sha256
from math import isfinite
from pathlib import Path
from statistics import mean

HORIZON=900

def ts(value):
    obj=datetime.fromisoformat(value)
    if obj.tzinfo is None:raise ValueError("naive_timestamp")
    return obj.timestamp()

def inspect(files):
    summaries=[]
    windows=set()
    unique_keys=set()
    all_signals=[]
    for path in files:
        blob=Path(path).read_bytes()
        data=json.loads(blob)
        if data.get("report_version")!="historical_m5_m15_shadow_v1":
            raise ValueError("wrong_strategy")
        if data.get("live_execution_enabled") is not False or data.get("model_promotion_allowed") is not False:
            raise ValueError("live_risk_wrong")
        if data.get("signal_timeframe")!="M5" or data.get("context_timeframe")!="M15":
            raise ValueError("incorrect_timeframe")
        period=(data["period"]["start"],data["period"]["end_exclusive"])
        if period in windows: raise ValueError("duplicate_window")
        windows.add(period)
        observed=0
        previous={}
        for rec in data["symbols"]:
            symbol=rec["symbol"]
            allowed={1:("BUY",),2:("SELL",),4:("BUY","SELL")}.get(rec.get("current_trade_mode"),())
            for item in rec.get("signals",[]):
                observed+=1
                if item["symbol"]!=symbol or item["side"] not in allowed:
                    raise ValueError("side_or_symbol_mismatch")
                close=ts(item["signal_bar_close_utc"])
                context=ts(item["context_bar_close_utc"])
                entry=ts(item["entry_tick_utc"])
                end=ts(item["exit_tick_utc"])
                if not 0<=close-context<=1800:
                    raise ValueError("lookahead_context")
                if not 0<=entry-close<=90 or not 900<=end-entry<=990:
                    raise ValueError("lookahead_quote")
                key=(symbol,close)
                if key in unique_keys:raise ValueError("duplicate_signal")
                unique_keys.add(key)
                if entry < previous.get(symbol,float("-inf")):
                    raise ValueError("overlapping_signal")
                previous[symbol]=entry+HORIZON
                bid,ask,xbid,xask=(item[x] for x in
                      ("entry_bid","entry_ask","exit_bid","exit_ask"))
                atr=item["signal_atr"]
                values=(bid,ask,xbid,xask,atr)
                if not all(isfinite(v) and v>0 for v in values) or ask<bid or xask<xbid:
                    raise ValueError("bad_bid_ask")
                spread=(ask-bid)/atr
                if abs(item["entry_spread_atr"]-spread)>1e-9 or (
                        item["cost_screen_pass"] is not (spread<=.15)):
                    raise ValueError("corrupt_spread_gate")
                delta=xbid-ask if item["side"]=="BUY" else bid-xask
                expected=delta/((bid+ask)/2)*10000
                if abs(expected-item["quoted_markout_bps"])>1e-7:
                    raise ValueError("corrupt_markout")
                for frame in ("m5","m15"):
                    digest=item.get(frame+"_evidence_sha256","")
                    if not re.fullmatch("[0-9a-f]{64}",digest):
                        raise ValueError("missing_frame_fingerprint")
                if item.get("live_risk_authorized") is not False or item.get("is_realized_pnl") is not False:
                    raise ValueError("incorrect_claim")
                all_signals.append(item)
        if data["signals_observed"]!=observed:
            raise ValueError("count_mismatch")
        summaries.append(dict(path=str(path),sha256=sha256(blob).hexdigest(),
            period=dict(start=period[0],end_exclusive=period[1]),
            scanned=data["symbols_scanned"],quoted_signals=observed,
            spread_pass=sum(1 for rec in data["symbols"]
                for s in rec.get("signals",[]) if s["cost_screen_pass"])))
    costs=[x for x in all_signals if x["cost_screen_pass"]]
    per_side={}
    for side in ("BUY","SELL"):
        values=[s["quoted_markout_bps"] for s in costs if s["side"]==side]
        per_side[side]=dict(observations=len(values),mean_quoted_markout_bps=mean(values)
                if values else None)
    return dict(kind="M5_M15_historical_tick_integrity_audit",
       input_windows=summaries,observed=len(all_signals),spread_pass=len(costs),
       spread_pass_by_side=per_side,context_timestamp_verified=True,
       model_promotion_allowed=False,live_execution_enabled=False,
       output_limitations=["Past data explored before; not untouched holdout.",
                           "No actual fills, SL/TP path, commissions, slippage, or macro vintages."])

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--report",nargs="+",required=True)
    p.add_argument("--output",required=True)
    args=p.parse_args()
    result=inspect(args.report)
    out=Path(args.output)
    if out.exists():raise FileExistsError("immutable_audit_exists")
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(result,indent=2,allow_nan=False)+"\n")
    print(json.dumps({k:result[k] for k in ("observed","spread_pass","spread_pass_by_side")},indent=2))
    print("AUDIT "+str(out))

if __name__=="__main__":
    main()
