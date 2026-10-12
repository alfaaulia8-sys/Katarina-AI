"""One durable research-only decision/quote-observation ledger.

Store all WAIT choices once per symbol/closed M5 bar. Only later
observed bid/ask markouts are resolved; NEVER count them as fills,
commission-reconciled net R, profitable trades or trained alpha.
"""
from __future__ import annotations
from datetime import datetime, timezone
from math import isfinite
import json
import sqlite3

HORIZON=900
MAX_EXIT_DELAY=120


def ts(value):
    x=datetime.fromisoformat(value.replace("Z","+00:00"))
    if x.tzinfo is None:raise ValueError("aware_clock_required")
    return x.timestamp()


class ContextDecisionJournal:
    def __init__(self,db:sqlite3.Connection):
        self.db=db
        db.execute("""CREATE TABLE IF NOT EXISTS contextual_decisions(
            id INTEGER PRIMARY KEY,
            symbol TEXT NOT NULL, closed_m5_utc TEXT NOT NULL,
            observed_utc TEXT NOT NULL, side TEXT NOT NULL,
            method TEXT NOT NULL, decision TEXT NOT NULL,
            blockers_json TEXT NOT NULL,
            entry_bid REAL, entry_ask REAL, entry_tick_epoch REAL,
            due_epoch REAL, status TEXT NOT NULL,
            exit_tick_epoch REAL, markout_bps REAL,
            UNIQUE(symbol,closed_m5_utc)
        )""")
        db.execute("""CREATE INDEX IF NOT EXISTS contextual_pending_due
            ON contextual_decisions(status,due_epoch)""")
        db.commit()

    def record(self,*,symbol,closed_m5_utc,observed_utc,
               side,method,decision,blockers,bid,ask,tick_epoch):
        if not symbol or side not in ("BUY","SELL","WAIT"):
            raise ValueError("invalid_symbol_or_side")
        now=ts(observed_utc); close=ts(closed_m5_utc)
        if close>now or now-close>1200:
            raise ValueError("stale_or_future_signal_bar")
        if side in ("BUY","SELL"):
            if (not all(isinstance(v,(int,float)) and isfinite(v) for v in (bid,ask,tick_epoch))
                    or bid<=0 or ask<bid or abs(now-tick_epoch)>180):
                raise ValueError("invalid_bid_ask_or_tick_clock")
            status="PENDING"; due=now+HORIZON
        else:
            status="NO_SIGNAL";due=None;bid=ask=tick_epoch=None
        with self.db:
            self.db.execute("""INSERT OR IGNORE INTO contextual_decisions(
                symbol,closed_m5_utc,observed_utc,side,method,decision,
                blockers_json,entry_bid,entry_ask,entry_tick_epoch,due_epoch,status
            ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)""",
                (symbol,closed_m5_utc,observed_utc,side,method,decision,
                 json.dumps(tuple(blockers)),bid,ask,tick_epoch,due,status))
        return self.db.execute(
            "SELECT changes()").fetchone()[0]==1

    def resolve(self,quotes,now):
        """quotes[symbol]=(bid,ask,verified_quote_utc_epoch).

        Only quotes within 120s of exact due time close a markout.
        If sampling missed that window, result is MISSING_EXIT,
        not a fabricated success.
        """
        if now.tzinfo is None:raise ValueError("now_requires_timezone")
        when=now.timestamp()
        n=0
        with self.db:
            rows=self.db.execute("""SELECT id,symbol,side,entry_bid,entry_ask,
              due_epoch FROM contextual_decisions
              WHERE status='PENDING' AND due_epoch<=?""",(when,)).fetchall()
            for iid,symbol,side,bid,ask,due in rows:
                quote=quotes.get(symbol)
                if quote is not None:
                    b,a,q=quote
                    valid=(all(isfinite(v) for v in (b,a,q))
                           and 0<b<=a and due<=q<=min(due+MAX_EXIT_DELAY,when))
                    if valid:
                        mid=(bid+ask)/2
                        raw=(b-ask if side=="BUY" else bid-a)
                        self.db.execute("""UPDATE contextual_decisions
                            SET status='QUOTED',exit_tick_epoch=?,markout_bps=?
                            WHERE id=? AND status='PENDING'""",
                            (q,raw/mid*10000,iid))
                        n+=1
                        continue
                if when>due+MAX_EXIT_DELAY:
                    self.db.execute("""UPDATE contextual_decisions
                        SET status='MISSING_EXIT' WHERE id=? AND status='PENDING'""",(iid,))
        return n

    def summary(self):
        counts=dict(self.db.execute(
            "SELECT status,COUNT(*) FROM contextual_decisions GROUP BY status"))
        latest=self.db.execute(
            "SELECT MAX(observed_utc) FROM contextual_decisions").fetchone()[0]
        return {"counts":counts,"last_observation_utc":latest,
                "outcome_type":"15min_BID_ASK_QUOTE_MARKOUT_NOT_EXECUTED_TRADING_PNL",
                "sample_overlap_possible":True,
                "broker_commission_verified":False,
                "usable_as_ResolvedExperience":False,
                "live_execution_authorized":False}
