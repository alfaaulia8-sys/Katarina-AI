"""Inspect broker-supported priority markets using Market Decision Brain V3.

Read-only evidence collection. No order_send, broker credentials, account
modifications, approved strategy-edge claim or live-trading activation.
"""
from __future__ import annotations
import json
from collections import Counter
from datetime import datetime,timezone,timedelta
from pathlib import Path
import MetaTrader5 as mt5
from katarina.intelligence.market_decision_brain_v3 import MarketDecisionBrain
from katarina.intelligence.broker_scan_universe import resolve_broker_symbols
from katarina.intelligence.broker_clock_alignment import infer_clock_shift
from katarina.intelligence.market_decision_pipeline import SensorCandle

TF={"M5":(mt5.TIMEFRAME_M5,5),"M15":(mt5.TIMEFRAME_M15,15),
    "H1":(mt5.TIMEFRAME_H1,60)}
DEST=Path(r"C:\KatarinaDev\decision-outputs-20261012\market_cards.json")
def bars_for(symbol, clock_correction: timedelta):
    result={}
    for label,(frame,minutes) in TF.items():
        rates=mt5.copy_rates_from_pos(symbol,frame,1,130)
        if rates is None or len(rates)<55:
            raise ValueError("insufficient_closed_"+label)
        result[label]=[
            SensorCandle(datetime.fromtimestamp(int(x["time"]),timezone.utc)
                         -clock_correction+timedelta(minutes=minutes),
                         float(x["open"]),float(x["high"]),float(x["low"]),
                         float(x["close"]),float(x["tick_volume"]))
            for x in rates]
    return result
def run():
    now=datetime.now(timezone.utc)
    if not mt5.initialize():
        raise RuntimeError("broker read-only connection unavailable")
    term=mt5.terminal_info()
    if term.trade_allowed:
        mt5.shutdown()
        raise RuntimeError("live MT5 session enabled: refusing automatic research scan")
    catalog=mt5.symbols_get()
    if catalog is None:
        mt5.shutdown();raise RuntimeError("broker_catalog_unavailable")
    selection=resolve_broker_symbols(catalog)
    symbols=list(selection.symbols)
    # Only current broker-advertised, selected markets may vote on the
    # read-only clock consensus; no fixed .vx reference is required.
    tick_clocks={}
    for ref in symbols:
        tick=mt5.symbol_info_tick(ref)
        if tick is not None and tick.bid>0 and tick.ask>=tick.bid:
            tick_clocks[ref]=int(tick.time)
    clock=infer_clock_shift(tick_clocks,now.timestamp())
    if not clock.suitable_for_readonly_snapshot:
        mt5.shutdown()
        raise RuntimeError("broker_server_utc_offset_cannot_be_verified")
    verified_hours=clock.observed_hours_shift
    brain=MarketDecisionBrain()
    output={"mode":"READ_ONLY_ADVISORY","as_of_utc":now.isoformat(),
            "source":"MT5 broker closed candles / current quote",
            "news_context_verified":False,
            "strategy_edge_registry":"EMPTY_UNTIL_INDEPENDENT_EVIDENCE",
            "live_execution_authorized":False,
            "orders_submitted":0,"verified_server_offset_hours":verified_hours,
            "broker_symbol_matches":selection.matches,
            "unavailable_broker_symbols":list(selection.unavailable),
            "broker_clock_confirming_symbols":clock.confirming_symbols,
            "symbols":{}}
    try:
        for symbol in symbols:
            try:
                mt5.symbol_select(symbol,True)
                info=mt5.symbol_info(symbol)
                tick=mt5.symbol_info_tick(symbol)
                valid_tick=tick is not None and tick.bid>0 and tick.ask>=tick.bid
                # Keep stale or slightly future-stamped symbol quotes from
                # satisfying the entry gate; a verified terminal-level offset
                # may still be used for descriptive *closed-bar* market state.
                age=(verified_hours*3600-(float(tick.time)-now.timestamp())) if valid_tick else None
                fresh_tick=age is not None and 0<=age<=180
                b=bars_for(symbol,timedelta(hours=verified_hours))
                closed_fresh=all(
                    timedelta(0)<=now-b[k][-1].closed_at_utc<=timedelta(minutes=m*2)
                    for k,(_,m) in TF.items())
                live_session=bool(fresh_tick and closed_fresh and info is not None
                                  and info.trade_mode!=mt5.SYMBOL_TRADE_MODE_DISABLED)
                spread=float(tick.ask-tick.bid) if valid_tick else float("nan")
                result=brain.evaluate(symbol=symbol,candles=b,as_of_utc=now,
                                      actual_spread=spread,broker_session_open=live_session,
                                      data_fresh=closed_fresh,
                                      news_blackout=False,news_context_verified=False,
                                      strategy_evidence={},risk_approved_for_paper=False)
                card=result.to_dict()
                card["quote_fresh"]=fresh_tick
                card["broker_server_to_utc_hours"]=verified_hours
                card["closed_bars_fresh"]=closed_fresh
                card["quote_age_sec"]=round(age,2) if age is not None else None
                output["symbols"][symbol]=card
            except (ValueError,TypeError,OverflowError,RuntimeError,IndexError) as err:
                output["symbols"][symbol]={"decision":"WAIT","technical_signal":"WAIT",
                    "market_state":"UNKNOWN","blockers":["sensor_error:"+type(err).__name__],
                    "live_execution_authorized":False}
    finally:
        mt5.shutdown()
    output["symbol_count"]=len(output["symbols"])
    output["states"]=dict(Counter(card["market_state"] for card in output["symbols"].values()))
    output["technical_signals"]=dict(Counter(card["technical_signal"] for card in output["symbols"].values()))
    output["decisions"]=dict(Counter(card["decision"] for card in output["symbols"].values()))
    DEST.parent.mkdir(parents=True,exist_ok=True)
    DEST.write_text(json.dumps(output,indent=2,ensure_ascii=False,allow_nan=False),encoding="utf-8")
    print("MARKET_DECISION_BRAIN_V3",json.dumps({
        "count":output["symbol_count"],"states":output["states"],
        "signals":output["technical_signals"],"decisions":output["decisions"],
        "examples":[{"symbol":sym,"state":c["market_state"],"direction":c.get("directional_bias"),
          "signal":c["technical_signal"],"decision":c["decision"],
          "evidence_score":c.get("evidence_score"),"reason":c.get("blockers",[])[:3]}
          for sym,c in output["symbols"].items() if sym in
             ("XAUUSD.vx","EURUSD.vx","USDJPY.vx","NAS100.vx")]},ensure_ascii=False))
if __name__=="__main__":
    run()