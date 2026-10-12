"""Run existing MarketDecisionBrain V3 on historical MT5 CLOSED bars, read-only.

Reuses adaptive_walkforward for outcome-delayed experience. Entry/exit
labels use M5 BID OHLC with ASSUMED spread, not broker tick fills,
and do NOT constitute fresh OOS. No historical news assumed. No orders.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime,timedelta,timezone
import json
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[2]/"src"))

from katarina.intelligence.broker_clock_alignment import infer_clock_shift
from katarina.intelligence.market_decision_pipeline import SensorCandle
from katarina.intelligence.causal_market_replay import (
    replay_native_brain,purged_chronological_splits
)
from katarina.intelligence.adaptive_walkforward import PaperEvent

ALLOWED=("XAUUSD.vx","EURUSD.vx","NAS100.vx","GBPUSD.vx","USDJPY.vx")


def load_from_live_terminal(symbols,*,max_cuts):
    import MetaTrader5 as mt5
    if not mt5.initialize():
        raise RuntimeError("MT5_TERMINAL_NOT_AVAILABLE")
    try:
        terminal=mt5.terminal_info()
        if terminal is None or terminal.trade_allowed:
            raise RuntimeError("HISTORICAL_REPLAY_REQUIRES_DISABLED_TRADE_PERMISSION")
        now=datetime.now(timezone.utc)
        readings={s:mt5.symbol_info_tick(s) for s in symbols}
        shift=infer_clock_shift(
            {s:int(t.time) for s,t in readings.items()
                if t is not None and t.bid>0 and t.ask>=t.bid},
            now.timestamp(),min_symbols=3)
        if not shift.suitable_for_readonly_snapshot:
            raise RuntimeError("CURRENT_BROKER_CLOCK_CONSENSUS_NOT_VERIFIED")
        frames={}
        status={}
        offset=shift.observed_hours_shift
        req={
            "M5":(mt5.TIMEFRAME_M5,max(1500,max_cuts+250),300),
            "M15":(mt5.TIMEFRAME_M15,900,900),
            "H1":(mt5.TIMEFRAME_H1,280,3600),
        }
        for symbol in symbols:
            bars={}
            for tf,(period,count,length) in req.items():
                rates=mt5.copy_rates_from_pos(symbol,period,1,count)
                if rates is None or len(rates)<60:
                    status[symbol]={"result":"NOT_ENOUGH_BROKER_BARS","timeframe":tf,
                                    "observed":0 if rates is None else len(rates)}
                    bars={}
                    break
                rows=[]
                for r in rates:
                    closed=datetime.fromtimestamp(int(r["time"])-offset*3600+length,
                                                  timezone.utc)
                    if closed>now:continue
                    rows.append(SensorCandle(
                        closed,float(r["open"]),float(r["high"]),
                        float(r["low"]),float(r["close"]),
                        float(r["tick_volume"])))
                bars[tf]=tuple(rows)
            if bars and all(len(v)>=60 for v in bars.values()):
                frames[symbol]=bars
                status[symbol]={"result":"AVAILABLE",
                                "counts":{k:len(v) for k,v in bars.items()},
                                "range_m5":[bars["M5"][0].closed_at_utc.isoformat(),
                                            bars["M5"][-1].closed_at_utc.isoformat()]}
        return frames,status,offset
    finally:
        mt5.shutdown()


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--symbols",default="XAUUSD.vx,EURUSD.vx,NAS100.vx")
    p.add_argument("--max-cuts",type=int,default=700)
    p.add_argument("--spread-to-atr",type=float,default=.04)
    p.add_argument("--extra-cost-r",type=float,default=.15)
    p.add_argument("--private-report",required=True)
    a=p.parse_args()
    symbols=[s.strip() for s in a.symbols.split(",") if s.strip()]
    if len(symbols)<3 or len(symbols)>5 or len(set(symbols))!=len(symbols) or any(s not in ALLOWED for s in symbols):
        p.error("3-5 supported symbols required for reliable broker clock vote")
    if not 120<=a.max_cuts<=1400:p.error("maximum 1400 retrospective cuts per symbol")
    frames,status,offset=load_from_live_terminal(symbols,max_cuts=a.max_cuts)
    if not frames:raise RuntimeError("NO_HISTORICAL_MARKET_BARS")
    result=replay_native_brain(
        frames,assumed_spread_to_m15_atr=a.spread_to_atr,
        additional_cost_r=a.extra_cost_r,
        max_m5_cuts_per_symbol=a.max_cuts)
    events=[PaperEvent(x["symbol"],x["method"],x["side"],
                       x["signal_at"],x["label_known_at"],
                       x["proxy_gross_r"],x["technical_score"],
                       a.spread_to_atr,market_regime=x["regime"])
            for x in result["signals"]]
    splits=purged_chronological_splits(events)
    summary=result["adaptive_summary"]
    info={
        "generated_utc":datetime.now(timezone.utc).isoformat(),
        "purpose":"CLOSED_BAR_REAL_MT5_HISTORICAL_SIGNAL_REPLAY",
        "read_only":True,"orders_sent":0,
        "broker_current_clock_offset_hours":offset,
        "broker_historical_clock_dst_verified":False,
        "actual_historical_spread_verified":False,
        "historical_news_contents_available":False,
        "retrospective_data_already_inspected_not_independent_holdout":True,
        "market_brain_reused":result["market_brain_reused"],
        "memory_engine_reused":result["memory_engine_reused"],
        "symbols_requested":symbols,
        "broker_data_availability":status,
        "counters":result["counters"],
        "assumed_spread_to_m15_atr":a.spread_to_atr,
        "additional_cost_r":a.extra_cost_r,
        "purged_calendar_split_counts":{
            "train":len(splits["train"]),
            "validation":len(splits["validation"]),
            "test":len(splits["test"]),
            "purged_or_embargoed":splits["purged"],
            "embargo_seconds":splits.get("embargo_sec"),
        },
        "adapted_replay":{
            "status":summary.get("status"),
            "adaptive":summary.get("adaptive"),
            "v6_conditional_benchmark":summary.get("v6_conditional_benchmark"),
            "replay_conditions":summary.get("replay_conditions"),
        },
        "candidate_methods":dict(Counter(x["method"] for x in result["signals"])),
        "no_qualified_live_strategy":True,
        "live_execution_authorized":False,
    }
    dest=Path(a.private_report)
    dest.parent.mkdir(parents=True,exist_ok=True)
    tmp=dest.with_suffix(".tmp")
    tmp.write_text(json.dumps(info,indent=2,allow_nan=False,ensure_ascii=False)+"\n",
                   encoding="utf-8")
    tmp.replace(dest)
    print("NATIVE_CAUSAL_BROKER_REPLAY",json.dumps({
        "symbols":list(frames),"cuts":result["counters"]["evaluated"],
        "paper_labels":result["counters"]["proxy_completed"],
        "train_val_test":info["purged_calendar_split_counts"],
        "candidate_methods":info["candidate_methods"],
        "adaptive_research":summary.get("adaptive",{}),
        "orders":0,"live":False},allow_nan=False))


if __name__=="__main__":
    main()
