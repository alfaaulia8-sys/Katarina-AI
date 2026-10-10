"""Read-only broker acquisition and auditable multi-market research screening."""
from __future__ import annotations
from datetime import datetime, timezone
from math import isfinite, sqrt
from statistics import mean
import json
from hashlib import sha256
from katarina.intelligence.market_universe import MarketTaxonomy

UTC = timezone.utc
FIAT = {"USD","EUR","GBP","JPY","CHF","CAD","AUD","NZD","CNY","CNH","HKD","SGD","MXN","ZAR","TRY","NOK","SEK","PLN"}


def features(bars, seconds, now):
    if len(bars) < 60:
        raise ValueError("insufficient_closed_bars")
    times = [int(b["time"]) for b in bars]
    if times != sorted(set(times)) or times[-1] + seconds > now.timestamp():
        raise ValueError("noncausal_or_duplicate_bars")
    for b in bars:
        values = [float(b[k]) for k in ("open","high","low","close")]
        if not all(isfinite(v) and v > 0 for v in values):
            raise ValueError("invalid_ohlc")
        if b["high"] < max(b["open"],b["close"],b["low"]) or b["low"] > min(b["open"],b["close"]):
            raise ValueError("invalid_ohlc")
    closes = [float(b["close"]) for b in bars]
    tr = [max(float(b["high"])-float(b["low"]), abs(float(b["high"])-closes[i-1]), abs(float(b["low"])-closes[i-1])) for i,b in enumerate(bars) if i]
    atr = mean(tr[-14:])
    if atr <= 0:
        raise ValueError("zero_volatility")
    def ema(period):
        value=closes[0]
        for close in closes[1:]:
            value += 2/(period+1)*(close-value)
        return value
    fast,slow=ema(20),ema(50)
    # Efficiency measures directional movement; not an ADX substitute.
    travel=sum(abs(b-a) for a,b in zip(closes[-21:-1],closes[-20:]))
    efficiency=abs(closes[-1]-closes[-21])/travel if travel else 0
    direction="UP" if closes[-1]>fast>slow else "DOWN" if closes[-1]<fast<slow else "MIXED"
    return dict(atr=atr,atr_bps=10000*atr/closes[-1],ema20=fast,ema50=slow,
                direction=direction,efficiency=efficiency,
                last_closed_utc=datetime.fromtimestamp(times[-1]+seconds,UTC).isoformat(),
                close_age_seconds=now.timestamp()-times[-1]-seconds,
                tick_activity_ratio=mean(float(b["tick_volume"]) for b in bars[-5:])/max(1,mean(float(b["tick_volume"]) for b in bars[-50:])),
                returns={str(times[i]):closes[i]/closes[i-1]-1 for i in range(1,len(times))})


def correlation(a,b):
    common=sorted(set(a)&set(b))
    if len(common)<30:
        return None
    x=[a[t] for t in common];y=[b[t] for t in common]
    mx,my=mean(x),mean(y)
    divisor=sqrt(sum((v-mx)**2 for v in x)*sum((v-my)**2 for v in y))
    return sum((v-mx)*(w-my) for v,w in zip(x,y))/divisor if divisor else None


def screen(rows, context, now, limit=5):
    output=[]
    for source in rows:
        row=dict(source)
        reasons=list(row.get("errors",[]))
        row["research_score"]=0.0
        row["action"]="NO_TRADE"
        row["live_risk_authorized"]=False
        mode=row.get("trade_mode",0)
        row["allowed_sides"]=["BUY","SELL"] if mode==4 else ["BUY"] if mode==1 else ["SELL"] if mode==2 else []
        if not row["allowed_sides"]:
            reasons.append("broker_disallows_new_positions")
        if not row.get("connected"):
            reasons.append("broker_disconnected")
        tick_age=now.timestamp()-row.get("tick_time",0)
        if not 0<=tick_age<=30:
            reasons.append("stale_or_future_quote")
        currencies=tuple(sorted({v for v in (row.get("base",""),row.get("profit","")) if v in FIAT}))
        row["context"]=context.assess(currencies,now) if currencies else dict(ready=False,reasons=["unknown_economic_exposure"])
        one=row.get("m1");five=row.get("m5")
        bid,ask=row.get("bid",0),row.get("ask",0)
        if not all(isfinite(v) and v>0 for v in (bid,ask)) or ask<bid:
            reasons.append("invalid_quote")
        elif one and five:
            ratio=(ask-bid)/one["atr"]
            row["spread_atr"]=ratio
            if ratio>0.15:
                reasons.append("spread_too_large")
            if one["close_age_seconds"]>120 or five["close_age_seconds"]>600:
                reasons.append("stale_bars")
            row["regime"]=five["direction"] if five["efficiency"]>=.3 else "RANGE_OR_NOISE"
            # Dimensionless activity/cost score, explicitly not a profit probability.
            row["research_score"]=one["atr_bps"]/(1+10*ratio)*min(2,one["tick_activity_ratio"])
        else:
            reasons.append("market_history_missing")
        row["market_reasons"]=sorted(set(reasons))
        row["decision_reasons"]=sorted(set(reasons+row["context"]["reasons"]+[
            "symbol_strategy_not_validated","commission_slippage_not_calibrated","session_schedule_not_verified"]))
        row["research_candidate"]=not reasons and row["context"]["ready"]
        output.append(row)
    ranked=sorted((r for r in output if r["research_candidate"]),key=lambda r:(-r["research_score"],r["symbol"]))
    selected=[]
    for row in ranked:
        linked=[(prior["symbol"],correlation(row["m1"]["returns"],prior["m1"]["returns"])) for prior in selected]
        row["correlations"]=dict(linked)
        if any(v is None or abs(v)>=.8 for _,v in linked):
            row["selection_reason"]="correlation_or_insufficient_overlap"
            continue
        if len(selected)>=limit:
            row["selection_reason"]="below_watchlist_limit"
            continue
        row["selection_reason"]="research_watchlist"
        selected.append(row)
    return dict(as_of_utc=now.isoformat(),symbols_scanned=len(output),
                research_watchlist=[r["symbol"] for r in selected],
                decision="NO_TRADE",live_execution_enabled=False,
                score_kind="relative_volatility_activity_spread_heuristic",
                symbols=output)


def collect(mt5, terminal_path):
    """No order API. Uses a specified research terminal; never arbitrary default."""
    if not mt5.initialize(terminal_path,timeout=15000):
        raise RuntimeError("research_terminal_unavailable")
    try:
        terminal=mt5.terminal_info()
        symbols=mt5.symbols_get()
        if terminal is None or symbols is None:
            raise RuntimeError("broker_catalog_unavailable")
        rows=[]
        for info in sorted(symbols,key=lambda x:x.name):
            row=dict(symbol=info.name,base=info.currency_base,profit=info.currency_profit,
                     trade_mode=info.trade_mode,connected=bool(terminal.connected),
                     asset_class=MarketTaxonomy.infer(info.name,info.currency_base,info.currency_profit).value,
                     contract_size=info.trade_contract_size,lot_min=info.volume_min,
                     lot_max=info.volume_max,lot_step=info.volume_step,
                     stop_level_points=info.trade_stops_level,errors=[])
            if info.trade_mode not in (1,2,4):
                row["errors"].append("broker_disallows_new_positions")
                rows.append(row);continue
            # Subscription is restricted to research terminal and enables history retrieval.
            if not mt5.symbol_select(info.name,True):
                row["errors"].append("symbol_subscription_failed")
                rows.append(row);continue
            tick=mt5.symbol_info_tick(info.name)
            if tick:
                row.update(bid=float(tick.bid),ask=float(tick.ask),tick_time=tick.time_msc/1000)
            else:
                row["errors"].append("quote_missing")
            for label,tf,seconds in (("m1",mt5.TIMEFRAME_M1,60),("m5",mt5.TIMEFRAME_M5,300)):
                rates=mt5.copy_rates_from_pos(info.name,tf,1,120)
                if rates is None:
                    row["errors"].append(label+"_history_unavailable");continue
                bars=[{k:float(r[k]) for k in ("time","open","high","low","close","tick_volume")} for r in rates]
                # Raw closed-bar evidence retained with the observation.
                row[label+"_bars"]=bars
                try:
                    row[label]=features(bars,seconds,datetime.now(UTC))
                except ValueError as exc:
                    row["errors"].append(label+"_"+str(exc))
            rows.append(row)
        return rows
    finally:
        mt5.shutdown()


def save_observation(store, result):
    # Deduplicate bar evidence; recurring scans should not copy identical histories.
    store.db.execute("CREATE TABLE IF NOT EXISTS market_evidence(sha256 TEXT PRIMARY KEY,payload TEXT)")
    for row in result.get("symbols", []):
        for tf in ("m1","m5"):
            bars = row.pop(tf+"_bars", None)
            if bars is not None:
                payload=json.dumps(bars,sort_keys=True,allow_nan=False)
                digest=sha256(payload.encode()).hexdigest()
                store.db.execute("INSERT OR IGNORE INTO market_evidence VALUES(?,?)",(digest,payload))
                row[tf+"_evidence_sha256"]=digest
            if tf in row:
                row[tf].pop("returns",None)
    store.db.execute("""CREATE TABLE IF NOT EXISTS brain_observations(
        id INTEGER PRIMARY KEY, observed_utc TEXT, decision TEXT, payload TEXT)""")
    store.db.execute("INSERT INTO brain_observations VALUES(NULL,?,?,?)",
                     (result["as_of_utc"],result["decision"],json.dumps(result,allow_nan=False)))
    store.db.commit()
