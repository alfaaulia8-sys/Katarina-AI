"""One canonical KATARINA read-only market + FULL-ARTICLE macro observer.

Runs ONE pass per scheduled invocation. Reuses existing broker scanner,
V3 candle reader, ContextStore official RSS/calendar cache, contextual
decision engine, and a separate quote-only observation journal.

Never uses the live/order gateway, never writes to GitHub, and never
automatically promotes signals. Legacy observers must remain disabled.
"""
from __future__ import annotations
from dataclasses import replace
from datetime import datetime,timedelta,timezone
from hashlib import sha256
from pathlib import Path
from collections import Counter
import argparse
import json
import os
import sqlite3
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[2]/"src"))

from katarina.intelligence.public_context import ContextStore,utc as parse_utc
from katarina.intelligence.broker_scan_universe import resolve_broker_symbols
from katarina.intelligence.broker_clock_alignment import infer_clock_shift
from katarina.intelligence.market_decision_brain_v3 import MarketDecisionBrain
from katarina.intelligence.contextual_decision_intelligence import RiskSituation
from katarina.intelligence.news_intelligence import (
    MultiSourceNewsEngine,NewsContext,
)
from katarina.intelligence.verified_policy_context import (
    ReadArticle,evidence_from_article,item_from_article,fetch_official_article,
    instrument_currencies,FRESH_SECONDS,
)
from katarina.intelligence.contextual_observation_journal import ContextDecisionJournal
from katarina.intelligence.market_article_context import collect_market_articles

# Single source for broker closed bars; no parallel V1/V2 feed workers.
from run_decision_brain_v3 import bars_for,TF


def lock_worker(root):
    """Fail fast on an existing worker. OS file locks disappear on crashes."""
    root.mkdir(parents=True,exist_ok=True)
    stream=(root/"worker.lock").open("a+b")
    try:
        if sys.platform=="win32":
            import msvcrt
            stream.seek(0)
            stream.write(b"0");stream.flush();stream.seek(0)
            msvcrt.locking(stream.fileno(),msvcrt.LK_NBLCK,1)
        else:
            import fcntl
            fcntl.flock(stream.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
    except OSError:
        stream.close()
        raise RuntimeError("CONTEXTUAL_OBSERVER_ALREADY_RUNNING")
    return stream


def ensure_article_table(store):
    store.db.execute("""CREATE TABLE IF NOT EXISTS contextual_official_articles(
        source TEXT NOT NULL,url TEXT NOT NULL,title TEXT NOT NULL,
        published TEXT NOT NULL,observed TEXT NOT NULL,
        body_digest TEXT NOT NULL,body TEXT NOT NULL,
        PRIMARY KEY(source,url))""")
    store.db.execute("""CREATE TABLE IF NOT EXISTS contextual_article_attempts(
        source TEXT NOT NULL,url TEXT NOT NULL,attempted TEXT NOT NULL,
        outcome TEXT NOT NULL, PRIMARY KEY(source,url))""")
    store.db.commit()


def load_articles(store,now):
    """At most one article fetch per source per pass; 30 min failure backoff."""
    ensure_article_table(store)
    diagnostics=Counter()
    for source in ("fed","ecb","boe"):
        snap=store.latest(source,now)
        if not snap["ready"]:
            diagnostics[source+"_feed_"+str(snap["reason"])]+=1
            continue
        articles=snap.get("payload",{}).get("items",[])
        newest=sorted(articles,key=lambda x:x.get("published_utc",""),reverse=True)
        for item in newest[:6]:
            try:
                published=parse_utc(item["published_utc"])
            except (ValueError,KeyError):
                continue
            if not 0<=(now-published).total_seconds()<=FRESH_SECONDS:
                continue
            url=item.get("url","")
            exists=store.db.execute(
                "SELECT 1 FROM contextual_official_articles WHERE source=? AND url=?",
                (source,url)).fetchone()
            if exists:
                diagnostics[source+"_full_text_cached"]+=1
                continue
            attempt=store.db.execute(
                "SELECT attempted FROM contextual_article_attempts WHERE source=? AND url=?",
                (source,url)).fetchone()
            if attempt and (now-parse_utc(attempt[0])).total_seconds()<1800:
                diagnostics[source+"_article_retry_backoff"]+=1
                continue
            try:
                body=fetch_official_article(url,source)
                digest=sha256(body.encode()).hexdigest()
                with store.db:
                    store.db.execute("""INSERT OR IGNORE INTO contextual_official_articles
                        VALUES(?,?,?,?,?,?,?)""",
                        (source,url,item["title"],published.isoformat(),
                         now.isoformat(),digest,body))
                diagnostics[source+"_full_text_verified"]+=1
            except Exception as exc:
                diagnostics[source+"_article_unavailable_"+type(exc).__name__]+=1
                with store.db:
                    store.db.execute("""INSERT OR REPLACE INTO contextual_article_attempts
                        VALUES(?,?,?,?)""",(source,url,now.isoformat(),
                                              type(exc).__name__))
            break  # bounded external fetch and CPU, no scraping loops
    results=[]
    for source,url,title,published,observed,digest,body in store.db.execute(
        """SELECT source,url,title,published,observed,body_digest,body
        FROM contextual_official_articles ORDER BY published DESC LIMIT 30"""):
        try:
            pub=parse_utc(published);obs=parse_utc(observed)
            if not (pub<=obs<=now and 0<=(now-pub).total_seconds()<=FRESH_SECONDS):
                continue
            if len(body.split())<95 or sha256(body.encode()).hexdigest()!=digest:
                diagnostics["cached_article_digest_or_body_invalid"]+=1
                continue
            results.append(ReadArticle(source,url,title,pub,obs,body,digest))
        except (ValueError,KeyError,TypeError):
            diagnostics["cached_article_invalid"]+=1
    return results,dict(diagnostics)


def calendar_status(store,now,currencies):
    snap=store.latest("calendar",now)
    if not snap["ready"]:
        return False,True,"calendar_missing_or_stale"
    data=snap.get("payload",{})
    try:
        if not (parse_utc(data["coverage_from"])<=now<
                parse_utc(data["coverage_to"])-timedelta(minutes=30)):
            return False,True,"calendar_outside_time_coverage"
        coverage=set(data["coverage"])
        if not set(currencies).issubset(coverage):
            return False,True,"calendar_currency_missing"
        blocked=[]
        for event in data["events"]:
            minutes=(parse_utc(event["event_utc"])-now).total_seconds()/60
            if (event["impact"]>=2 and event["currency"] in
                (set(currencies)|{"ALL"}) and -15<=minutes<=30):
                blocked.append(event["name"])
        return True,bool(blocked),"economic_blackout" if blocked else "calendar_verified_clear"
    except (KeyError,TypeError,ValueError):
        return False,True,"calendar_schema_error"


def prepare_news(articles,symbol,now,store):
    macro=[];items=[];sources=[]
    for article in articles:
        try:
            e=evidence_from_article(article,symbol,now)
            if e is None:continue
            news_item=item_from_article(article,symbol,now)
            if news_item is None:continue
            macro.append(e);items.append(news_item)
            sources.append(dict(
                source=article.source_id,url=article.url,
                published_utc=article.published_at_utc.isoformat(),
                observed_utc=article.observed_at_utc.isoformat(),
                body_digest_sha256=article.sha256,
                body_word_count=len(article.body.split()),
                policy_direction=e.policy_direction,
                hypothesized_side=e.favored_side,
                transmission_mechanism=e.transmission_mechanism,
                full_text_read=True,
            ))
        except (ValueError,TypeError,KeyError):
            continue
    news=MultiSourceNewsEngine().assess(
        tuple(items),exposures=instrument_currencies(symbol),now_utc=now)
    calendar_ready,calendar_blackout,calendar_reason=calendar_status(
        store,now,instrument_currencies(symbol))
    # Real calendar failure blocks the signal; lack of article does NOT
    # invent a news blackout event, but NewsContext stays not ready.
    news=replace(news,blackout=news.blackout or calendar_blackout,
        reasons=tuple(news.reasons)+(calendar_reason,))
    return news,macro,sources,{
        "ready":calendar_ready,"blackout":calendar_blackout,
        "reason":calendar_reason,
    }


def publish(root,data):
    target=root/"latest.json"
    temp=root/"latest.tmp"
    raw=(json.dumps(data,ensure_ascii=False,indent=2,allow_nan=False)+"\n").encode()
    temp.write_bytes(raw)
    # Do not fallback to overwriting ACL-locked files owned by legacy observers.
    temp.replace(target)


def observe(root,*,max_symbols=17,fetch_news=True):
    import MetaTrader5 as mt5

    if not mt5.initialize():
        raise RuntimeError("BROKER_NOT_CONNECTED")
    term=mt5.terminal_info()
    if term is None or term.trade_allowed:
        mt5.shutdown()
        raise RuntimeError("FAIL_CLOSED_TRADING_MUST_BE_DISABLED")
    store=None
    try:
        feed_started_at=datetime.now(timezone.utc)
        store=ContextStore(root/"context.sqlite3")
        journal=ContextDecisionJournal(store.db)
        feed_status=store.refresh(feed_started_at) if fetch_news else {
            s:"OFFLINE_TEST_DISABLED" for s in ("fed","ecb","boe","calendar")}
        # ContextStore.record timestamps are captured AFTER a network request;
        # the original feed_started_at is before those snapshots, so using it
        # to query the cache would silently hide every newly fetched article.
        articles,article_diag=load_articles(store,datetime.now(timezone.utc))
        # Media article body provides contextual interpretation only.
        # NEVER convert it into an official monetary-policy trade signal.
        media_analysis,media_status=collect_market_articles(
            store.db,datetime.now(timezone.utc)) if fetch_news else ([],("disabled",))
        now=datetime.now(timezone.utc)
        catalog=mt5.symbols_get()
        if catalog is None:raise RuntimeError("BROKER_CATALOG_NOT_FOUND")
        selection=resolve_broker_symbols(catalog)
        symbols=list(selection.symbols)[:max_symbols]
        if not symbols:raise RuntimeError("NO_ELIGIBLE_BROKER_SYMBOLS")
        ticks={sym:mt5.symbol_info_tick(sym) for sym in symbols}
        clock=infer_clock_shift({
            sym:int(t.time) for sym,t in ticks.items()
            if t is not None and t.bid>0 and t.ask>=t.bid},
            now.timestamp())
        if not clock.suitable_for_readonly_snapshot:
            raise RuntimeError("BROKER_CLOCK_NOT_VERIFIED")
        offset=clock.observed_hours_shift
        correction=timedelta(hours=offset)
        brain=MarketDecisionBrain()
        report={"schema":1,"mode":"READ_ONLY_CONTEXTUAL_ONE_CANONICAL_OBSERVER",
                "observed_at_utc":now.isoformat(),"broker_server_shift_hours":offset,
                "historical_clock_shift_verified":False,
                "broker_clock_confirming_symbols":clock.confirming_symbols,
                "news_feed_status":feed_status,"full_article_checks":article_diag,
                "media_article_status":list(media_status),
                "media_articles_analyzed_from_body":media_analysis[:8],
                "media_alone_never_authorizes_entry":True,
                "news_policy_method":"OFFICIAL_PUBLISHER_FULL_ARTICLE_CONDITIONAL_ONLY",
                "broker_symbol_matches":selection.matches,
                "unavailable_symbols":list(selection.unavailable),
                "news_body_missing_never_replaced_by_headline":True,
                "real_account_risk_not_connected":True,
                "forward_trade_outcomes_not_verified":True,
                "production_execution":False,
                "live_execution_authorized":False,"orders_submitted":0,"symbols":{}}
        latest_quotes={}
        for symbol in symbols:
            tick=ticks.get(symbol)
            try:
                if not mt5.symbol_select(symbol,True):
                    raise ValueError("symbol_select_denied")
                info=mt5.symbol_info(symbol)
                if info is None or tick is None or tick.bid<=0 or tick.ask<tick.bid:
                    raise ValueError("invalid_symbol_or_quote")
                quote_at=tick.time-offset*3600
                quote_age=now.timestamp()-quote_at
                quote_fresh=(-15<=quote_age<=180)
                raw_bars=bars_for(symbol,correction)
                # Broker timestamps currently lead system UTC by ~13s even
                # after integer-hour offset correction. Discard ANY candle
                # that has not closed at the actual observation UTC; never
                # accept a future bar just because the terminal returned it.
                bars={tf:[b for b in rows if b.closed_at_utc<=now]
                      for tf,rows in raw_bars.items()}
                if any(len(bars[tf])<55 for tf in TF):
                    raise ValueError("insufficient_past_only_closed_bars")
                recent=all(0<=(now-bars[k][-1].closed_at_utc).total_seconds()<=mins*120
                           for k,(_,mins) in TF.items())
                quote_ok=bool(quote_fresh and recent and info.trade_mode in (1,2,4))
                observed_spread=float(tick.ask-tick.bid)
                news,macro,sources,calendar=prepare_news(articles,symbol,now,store)
                # Real account position book/capital-risk telemetry NOT
                # retrieved. Mark system_healthy FALSE so even a future
                # statistically good paper history cannot start execution.
                risk=RiskSituation(
                    system_healthy=False,broker_session_open=quote_ok,
                    quote_fresh=quote_fresh,drawdown_fraction=0,
                    realized_daily_loss_r=0,open_positions=0,
                    gross_exposure_fraction=0)
                decision=brain.evaluate_contextually(
                    symbol=symbol,candles=bars,as_of_utc=now,
                    actual_spread=observed_spread,news_context=news,
                    macro_evidence=macro,resolved_experience=[],
                    risk_situation=risk)
                card=decision.to_dict()
                card["broker_quote_age_seconds"]=round(quote_age,2)
                card["broker_spread_price"]=round(observed_spread,8)
                card["closed_bar_times_utc"]={
                    tf:bars[tf][-1].closed_at_utc.isoformat() for tf in TF}
                card["calendar"]=calendar
                card["verified_full_text_articles"]=sources[:5]
                card["costs_reconciled"]=False
                card["news_economic_feed_ready"]=news.ready and calendar["ready"]
                card["quote_markout_is_real_trade"]=False
                report["symbols"][symbol]=card
                latest_quotes[symbol]=(float(tick.bid),float(tick.ask),quote_at)
                if quote_ok:
                    try:
                        journal.record(
                            symbol=symbol,closed_m5_utc=bars["M5"][-1].closed_at_utc.isoformat(),
                            observed_utc=now.isoformat(),side=decision.conditional_side,
                            method=decision.selected_method,decision=decision.action,
                            blockers=decision.blocking_reasons,
                            bid=float(tick.bid),ask=float(tick.ask),tick_epoch=quote_at)
                    except (ValueError,TypeError):
                        card["journal_status"]="REJECTED_INVALID_TIMESTAMP_OR_QUOTE"
            except Exception as ex:
                report["symbols"][symbol]={
                    "action":"WAIT","conditional_side":"WAIT",
                    "market_state":"UNKNOWN","blocking_reasons":["sensor_error:"+type(ex).__name__],
                    "live_execution_authorized":False,
                }
        report["quote_markouts_resolved_this_cycle"]=journal.resolve(latest_quotes,now)
        report["quote_journal"]=journal.summary()
        report["market_states"]=dict(Counter(
            x["market_state"] for x in report["symbols"].values()))
        report["final_actions"]=dict(Counter(
            x["action"] for x in report["symbols"].values()))
        report["observed_symbols"]=len(report["symbols"])
        publish(root,report)
        return {"observed_symbols":report["observed_symbols"],
                "market_states":report["market_states"],"final_actions":report["final_actions"],
                "full_articles":len(articles),"clock_hours":offset,
                "journal":report["quote_journal"]["counts"],"orders":0}
    finally:
        if store is not None:store.db.close()
        mt5.shutdown()


def main():
    p=argparse.ArgumentParser()
    p.add_argument("--state-dir",default=r"C:\KatarinaDev\artifacts\contextual-observer")
    p.add_argument("--max-symbols",type=int,default=17)
    p.add_argument("--no-fetch",action="store_true",help="Offline debugging; never bypass news gates")
    args=p.parse_args()
    if not 1<=args.max_symbols<=17:p.error("max 17 broker markets")
    root=Path(args.state_dir)
    lock=lock_worker(root)
    try:
        result=observe(root,max_symbols=args.max_symbols,fetch_news=not args.no_fetch)
        print("KATARINA_CONTEXTUAL_ONE_PASS",json.dumps(result,sort_keys=True),flush=True)
    finally:
        lock.close()


if __name__=="__main__":
    main()
