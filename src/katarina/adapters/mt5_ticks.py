from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Iterable, Iterator

from katarina.research.real_tick import Tick


@dataclass(frozen=True, slots=True)
class MT5TickSourceStatus:
    initialized: bool
    terminal_path: str
    last_error: object | None


class MT5TickSource:
    """Read-only adapter from MetaTrader5.copy_ticks_range to KATARINA Tick.

    MetaTrader5 is imported lazily so CI/research environments without the
    Windows package can still import KATARINA normally.
    """

    def __init__(self, mt5_module=None):
        self._mt5=mt5_module
        self._initialized=False
        self._terminal_path=""

    def _module(self):
        if self._mt5 is None:
            import MetaTrader5 as mt5  # type: ignore
            self._mt5=mt5
        return self._mt5

    def initialize(self, terminal_path: str, *, timeout_ms: int=15000) -> MT5TickSourceStatus:
        mt5=self._module()
        ok=bool(mt5.initialize(path=terminal_path,timeout=timeout_ms))
        self._initialized=ok
        self._terminal_path=terminal_path
        return MT5TickSourceStatus(ok,terminal_path,None if ok else mt5.last_error())

    def close(self) -> None:
        if self._mt5 is not None:
            try:self._mt5.shutdown()
            except Exception:pass
        self._initialized=False

    def copy_range(self, symbol:str, start_utc:datetime, end_utc:datetime) -> tuple[Tick,...]:
        if not self._initialized:
            raise RuntimeError("MT5 tick source not initialized")
        mt5=self._module()
        if start_utc.tzinfo is None:start_utc=start_utc.replace(tzinfo=timezone.utc)
        if end_utc.tzinfo is None:end_utc=end_utc.replace(tzinfo=timezone.utc)
        if end_utc<=start_utc:
            raise ValueError("end_utc must be after start_utc")
        if not mt5.symbol_select(symbol,True):
            raise RuntimeError(f"symbol_select failed: {mt5.last_error()}")
        rows=mt5.copy_ticks_range(symbol,start_utc,end_utc,mt5.COPY_TICKS_ALL)
        if rows is None:
            raise RuntimeError(f"copy_ticks_range failed: {mt5.last_error()}")
        out=[]
        for row in rows:
            bid=float(row["bid"]);ask=float(row["ask"])
            if bid<=0 or ask<=0 or ask<bid:
                continue
            if "time_msc" in getattr(row,"dtype",()).names if getattr(row,"dtype",None) is not None else False:
                ts=int(row["time_msc"])*1_000_000
            else:
                try:ts=int(row["time_msc"])*1_000_000
                except Exception:ts=int(row["time"])*1_000_000_000
            out.append(Tick(ts,bid,ask))
        return tuple(out)

    def iter_chunks(
        self,
        symbol:str,
        start_utc:datetime,
        end_utc:datetime,
        *,
        chunk:timedelta=timedelta(days=1),
    ) -> Iterator[tuple[Tick,...]]:
        if chunk.total_seconds()<=0:raise ValueError("chunk")
        cursor=start_utc
        while cursor<end_utc:
            nxt=min(end_utc,cursor+chunk)
            yield self.copy_range(symbol,cursor,nxt)
            cursor=nxt
