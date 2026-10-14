"""Read-only MT5 account P/L adapter for Katarina's existing risk ledger.

The caller provides an already-authorized MT5 session. This module NEVER logs
in, starts a terminal, selects symbols, changes orders, or places trades.

A broker session and a complete broker history cannot be cryptographically
authenticated by the Python MT5 SDK. Consequently all outputs remain offline
risk evidence and NEVER authorize Owner Extreme Recovery/live execution.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from math import isfinite
from typing import Any

from katarina.engines.manual_risk import (
    BrokerLossAttribution,
    BrokerPnLReconciler,
    PositionPnLChange,
)


@dataclass(frozen=True, slots=True)
class Mt5MarkedPosition:
    position_id: str
    origin: str
    floating_pnl: float


@dataclass(frozen=True, slots=True)
class Mt5AccountMark:
    account_login: int
    broker_server: str
    account_currency: str
    equity: float
    captured_utc_ns: int
    positions: tuple[Mt5MarkedPosition, ...]


@dataclass(frozen=True, slots=True)
class Mt5PnLObservation:
    attribution: BrokerLossAttribution
    deal_count: int
    position_count_before: int
    position_count_after: int
    external_cash_flow: float
    # Refuse caller-supplied positive attestation flags on this read-only
    # evidence class. Broker provenance cannot be asserted by these methods.
    broker_history_complete_verified: bool = field(default=False, init=False)
    server_trading_day_authenticated: bool = field(default=False, init=False)
    live_execution_authorized: bool = field(default=False, init=False)


class Mt5ReadOnlyPnLAdapter:
    """Mark two broker snapshots with only read operations; reconcile deals.

    No caller-controlled 'reconciled=True' claim is generated. Unsupported
    origin, ledger types, gaps, account switches or missing data fail closed.
    """

    def __init__(self, mt5: Any, *, katarina_magic: int):
        if type(katarina_magic) is not int or katarina_magic <= 0:
            raise ValueError("katarina_magic_required")
        self._mt5 = mt5
        self._magic = katarina_magic

    @staticmethod
    def _cash(value: Any, label: str) -> float:
        if isinstance(value, bool):
            raise ValueError("invalid_" + label)
        try:
            n = float(value)
        except (ValueError, TypeError, OverflowError) as exc:
            raise ValueError("invalid_" + label) from exc
        if not isfinite(n):
            raise ValueError("invalid_" + label)
        return n

    def _origin(self, reason: Any, magic: Any, *, position: bool) -> str:
        m = self._mt5
        prefix = "POSITION_REASON_" if position else "DEAL_REASON_"
        known = (
            ("CLIENT", "MANUAL_DESKTOP"),
            ("MOBILE", "MANUAL_MOBILE"),
            ("WEB", "MANUAL_WEB"),
        )
        for suffix, origin in known:
            code = getattr(m, prefix + suffix, None)
            if type(code) is int and reason == code:
                return origin
        expert = getattr(m, prefix + "EXPERT", None)
        if type(expert) is int and reason == expert:
            return "KATARINA" if magic == self._magic else "FOREIGN_EA"
        return "UNKNOWN"

    @staticmethod
    def _id(value: Any) -> str:
        if type(value) is not int or value <= 0:
            raise ValueError("invalid_broker_position_identifier")
        return str(value)

    def capture(self, *, captured_utc_ns: int) -> Mt5AccountMark:
        if type(captured_utc_ns) is not int or captured_utc_ns <= 0:
            raise ValueError("invalid_capture_time")
        account = self._mt5.account_info()
        positions = self._mt5.positions_get()
        if account is None or positions is None:
            raise RuntimeError("mt5_broker_snapshot_unavailable")
        # Refuse mixed-account marks if an operator switches the MT5 account
        # between account_info() and positions_get().
        again = self._mt5.account_info()
        if (again is None
                or any(getattr(account, field, None) !=
                       getattr(again, field, None)
                       for field in ("login", "server", "currency"))):
            raise RuntimeError("mt5_account_changed_during_snapshot")
        login = getattr(account, "login", None)
        if type(login) is not int or login <= 0:
            raise ValueError("invalid_mt5_login")
        broker_server = getattr(account, "server", None)
        account_currency = getattr(account, "currency", None)
        if (not isinstance(broker_server, str) or not broker_server.strip()
                or not isinstance(account_currency, str)
                or not account_currency.strip()):
            raise ValueError("unverified_mt5_broker_server_or_currency")
        equity = self._cash(getattr(account, "equity", None), "account_equity")
        if equity <= 0:
            raise ValueError("invalid_mt5_equity")
        marks = []
        seen = set()
        for position in positions:
            pid = self._id(getattr(position, "identifier", None))
            if pid in seen:
                raise ValueError("duplicate_open_position_identifier")
            seen.add(pid)
            floating = self._cash(getattr(position, "profit", None), "floating_profit")
            swap = self._cash(getattr(position, "swap", None), "floating_swap")
            origin = self._origin(
                getattr(position, "reason", None),
                getattr(position, "magic", None),
                position=True,
            )
            marks.append(Mt5MarkedPosition(pid, origin, floating + swap))
        return Mt5AccountMark(login, broker_server.strip(),
                              account_currency.strip(), equity,
                              captured_utc_ns, tuple(marks))

    def reconcile(self, before: Mt5AccountMark, after: Mt5AccountMark) -> Mt5PnLObservation:
        if (not isinstance(before, Mt5AccountMark)
                or not isinstance(after, Mt5AccountMark)
                or before.account_login != after.account_login
                or before.broker_server != after.broker_server
                or before.account_currency != after.account_currency
                or before.captured_utc_ns >= after.captured_utc_ns):
            raise ValueError("account_or_capture_window_mismatch")
        for snapshot in (before, after):
            if snapshot.account_login <= 0 or snapshot.equity <= 0:
                raise ValueError("invalid_account_identity_or_equity")
        begin = datetime.fromtimestamp(before.captured_utc_ns / 1e9, timezone.utc)
        end = datetime.fromtimestamp(after.captured_utc_ns / 1e9, timezone.utc)
        deals = self._mt5.history_deals_get(begin, end)
        if deals is None:
            raise RuntimeError("broker_deal_history_unavailable")
        # MT5 terminal accounts can be switched outside this Python process.
        # Reject history if it was fetched under a different broker login.
        rechecked = self._mt5.account_info()
        if (rechecked is None
                or getattr(rechecked, "login", None) != before.account_login
                or getattr(rechecked, "server", None) != before.broker_server
                or getattr(rechecked, "currency", None) != before.account_currency):
            raise RuntimeError("mt5_account_changed_during_history_read")

        old = {p.position_id: p for p in before.positions}
        new = {p.position_id: p for p in after.positions}
        if len(old) != len(before.positions) or len(new) != len(after.positions):
            raise ValueError("duplicate_broker_position_mark")
        origin = {}
        for pid in set(old) | set(new):
            old_origin = old[pid].origin if pid in old else None
            new_origin = new[pid].origin if pid in new else None
            if old_origin is not None and new_origin is not None and old_origin != new_origin:
                raise ValueError("position_origin_changed_during_window")
            origin[pid] = old_origin if old_origin is not None else new_origin
        realized = {}
        external_cash_flow = 0.0
        seen_deals = set()
        for deal in deals:
            ticket = getattr(deal, "ticket", None)
            when = getattr(deal, "time_msc", None)
            if type(ticket) is not int or ticket <= 0 or ticket in seen_deals:
                raise ValueError("missing_or_duplicate_mt5_deal_ticket")
            seen_deals.add(ticket)
            if type(when) is not int or not (
                    before.captured_utc_ns // 1_000_000 < when <=
                    after.captured_utc_ns // 1_000_000):
                raise ValueError("deal_timestamp_outside_capture_window")
            typ = getattr(deal, "type", None)
            profit = self._cash(getattr(deal, "profit", None), "deal_profit")
            if typ == getattr(self._mt5, "DEAL_TYPE_BALANCE", object()):
                external_cash_flow += profit
                continue
            if typ not in (
                    getattr(self._mt5, "DEAL_TYPE_BUY", object()),
                    getattr(self._mt5, "DEAL_TYPE_SELL", object())):
                raise ValueError("unsupported_mt5_ledger_operation")
            pid = self._id(getattr(deal, "position_id", None))
            fees = sum(self._cash(getattr(deal, field, None), "deal_" + field)
                       for field in ("commission", "fee", "swap"))
            realized[pid] = realized.get(pid, 0.0) + profit + fees
            # MT5 DEAL_REASON describes who initiated THIS execution, not
            # necessarily who OPENED and owns the underlying position.
            # A user closing Katarina's position (or automatic SL/TP close)
            # must NOT reattribute the entire P/L to the Owner.
            entry = getattr(deal, "entry", None)
            entry_in = getattr(self._mt5, "DEAL_ENTRY_IN", None)
            entry_out = getattr(self._mt5, "DEAL_ENTRY_OUT", None)
            entry_out_by = getattr(self._mt5, "DEAL_ENTRY_OUT_BY", None)
            entry_inout = getattr(self._mt5, "DEAL_ENTRY_INOUT", None)
            if (type(entry) is not int
                    or any(type(c) is not int for c in
                           (entry_in, entry_out, entry_out_by, entry_inout))):
                raise ValueError("missing_mt5_deal_entry_provenance")
            if entry == entry_in:
                opening_origin = self._origin(
                    getattr(deal, "reason", None),
                    getattr(deal, "magic", None),
                    position=False,
                )
                if pid not in origin or origin[pid] == "UNKNOWN":
                    origin[pid] = opening_origin
                elif opening_origin not in ("UNKNOWN", origin[pid]):
                    raise ValueError("broker_position_open_origin_conflict")
            elif entry in (entry_out, entry_out_by):
                # Closing reason is not position ownership evidence. For
                # positions closed entirely inside the window, a known
                # opening deal is REQUIRED to attribute their P/L.
                origin.setdefault(pid, "UNKNOWN")
            elif entry == entry_inout:
                # Netting reversals can change owners mid-position; without
                # volume-weighted lineage, conservatively reject the window.
                raise ValueError("mt5_netting_reversal_not_attributable")
            else:
                raise ValueError("unsupported_mt5_deal_entry")
        changes = []
        for pid in sorted(set(old) | set(new) | set(realized)):
            before_profit = old[pid].floating_pnl if pid in old else 0.0
            after_profit = new[pid].floating_pnl if pid in new else 0.0
            changes.append(PositionPnLChange(
                pid, origin.get(pid, "UNKNOWN"), realized.get(pid, 0.0),
                after_profit - before_profit,
            ))
        attribution = BrokerPnLReconciler.reconcile(
            previous_equity=before.equity, current_equity=after.equity,
            external_cash_flow=external_cash_flow, changes=changes,
        )
        return Mt5PnLObservation(
            attribution, len(seen_deals), len(old), len(new), external_cash_flow,
        )

class Mt5PnLReplayChain:
    """Reject noncontiguous or unreconciled offline broker snapshot windows.

    This is deterministic engineering evidence only. No live authorization,
    broker-session authentication, MT5 initialization, or trading operations.
    """

    def __init__(self, adapter: Mt5ReadOnlyPnLAdapter):
        if not isinstance(adapter, Mt5ReadOnlyPnLAdapter):
            raise TypeError("mt5_read_only_adapter_required")
        self._adapter = adapter
        self._last_after: Mt5AccountMark | None = None

    @property
    def last_after(self) -> Mt5AccountMark | None:
        return self._last_after

    def consume(self, before: Mt5AccountMark,
                after: Mt5AccountMark) -> Mt5PnLObservation:
        if self._last_after is not None and before != self._last_after:
            raise ValueError("noncontiguous_mt5_broker_replay_window")
        observation = self._adapter.reconcile(before, after)
        if not observation.attribution.balanced:
            raise RuntimeError("mt5_broker_replay_unreconciled")
        # Advance only on an accepted complete *arithmetic* window. This is
        # still not independent proof of complete broker historical coverage.
        self._last_after = after
        return observation
