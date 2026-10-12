"""Causal MT5 quote reader for the existing single read-only observer.

MT5 symbol_info_tick may carry a server-local +integer-hour offset
and a further seconds-level lead. Historical copy_ticks_range returns
UTC-epoch milliseconds on this broker. Never treat the latest server
tick as a quote observed in the future of the VPS's decision clock.

The functions require UTC timezone-aware boundaries, verify actual
tick timestamps and bid/ask, and NEVER send/check a broker order.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from math import isfinite

MAX_TICKS_PER_QUERY=25000


def aware_utc(timestamp):
    if not isinstance(timestamp,datetime) or timestamp.tzinfo is None:
        raise ValueError("quote_clock_must_have_timezone")
    return timestamp.astimezone(timezone.utc)


def _fetch_ticks(mt5,symbol,start,end):
    if not symbol or end<=start:
        return ()
    a=mt5.copy_ticks_range(symbol,start,end,mt5.COPY_TICKS_INFO)
    if a is None or len(a)>MAX_TICKS_PER_QUERY:
        return ()
    return a


def _verified_quote(row,lower,upper):
    try:
        ts=float(row["time_msc"])/1000.0
        bid=float(row["bid"]);ask=float(row["ask"])
    except (KeyError,TypeError,ValueError,IndexError):
        return None
    if (not all(isfinite(v) for v in (ts,bid,ask)) or
        bid<=0 or ask<bid or ts<lower or ts>upper):
        return None
    return (bid,ask,ts)


def last_past_quote(mt5,symbol,as_of_utc,lookback_seconds=90):
    """Freshest real BID/ASK price quote with timestamp <= observed clock.

    Do not extrapolate data from a tick in the broker's future;
    no interpolation, normalization by guessing a fractional offset,
    or acceptance of a quote older than the bounded lookback.
    """
    now=aware_utc(as_of_utc)
    if not 0<lookback_seconds<=180:
        raise ValueError("invalid_quote_lookback")
    before=now-timedelta(seconds=lookback_seconds)
    arr=_fetch_ticks(mt5,symbol,before,now)
    upper=now.timestamp();lower=before.timestamp()
    # A stable maximum, rather than assuming broker arrays are sorted.
    matched=[q for q in (_verified_quote(row,lower,upper) for row in arr)
             if q is not None]
    return max(matched,key=lambda q:q[2]) if matched else None


def due_window_quote(mt5,symbol,due_epoch,now_epoch,max_delay=120):
    """Earliest actual tick after a precommitted markout deadline.

    This may be queried later (next 5-min cycle) via broker history;
    mark as RETROSPECTIVELY RECONCILED, not a real-time paper fill.
    Broker history uses UTC timestamps, NOT current terminal offset.
    """
    due=float(due_epoch);now=float(now_epoch)
    if (not all(isfinite(x) for x in (due,now)) or
        not 0<max_delay<=180 or due>=now):
        return None
    end=min(now,due+max_delay)
    if end<=due:
        return None
    arr=_fetch_ticks(
        mt5,symbol,datetime.fromtimestamp(due,timezone.utc),
        datetime.fromtimestamp(end,timezone.utc),
    )
    matched=[q for q in (_verified_quote(row,due,end) for row in arr)
             if q is not None]
    return min(matched,key=lambda q:q[2]) if matched else None
