from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum
from typing import Any, Mapping

from katarina.core.readiness import ReadinessGate, ReadinessSignal


class HealthState(IntEnum):
    UNKNOWN = 0
    OK = 1
    DEGRADED = 2
    BLOCKED = 3


@dataclass(frozen=True, slots=True)
class HealthPolicy:
    heartbeat_stale_ns: int = 5_000_000_000
    health_event_stale_ns: int = 5_000_000_000
    broker_observation_stale_ns: int = 5_000_000_000
    clock_degraded_skew_ns: int = 2_000_000_000
    clock_blocked_skew_ns: int = 10_000_000_000
    ping_degraded_us: int = 250_000
    ping_blocked_us: int = 1_000_000
    rtt_degraded_us: int = 250_000
    rtt_blocked_us: int = 1_000_000
    critical_queue_degraded_depth: int = 1536
    critical_queue_blocked_depth: int = 2048
    market_queue_degraded_depth: int = 4096
    decode_error_hold_ns: int = 10_000_000_000
    healthy_streak_required: int = 2

    def __post_init__(self) -> None:
        positive = (
            self.heartbeat_stale_ns,
            self.health_event_stale_ns,
            self.broker_observation_stale_ns,
            self.clock_degraded_skew_ns,
            self.clock_blocked_skew_ns,
            self.ping_degraded_us,
            self.ping_blocked_us,
            self.rtt_degraded_us,
            self.rtt_blocked_us,
            self.critical_queue_degraded_depth,
            self.critical_queue_blocked_depth,
            self.market_queue_degraded_depth,
            self.decode_error_hold_ns,
            self.healthy_streak_required,
        )
        if any(value <= 0 for value in positive):
            raise ValueError("health policy thresholds must be positive")
        if self.clock_blocked_skew_ns <= self.clock_degraded_skew_ns:
            raise ValueError("clock blocked threshold must exceed degraded")
        if self.ping_blocked_us <= self.ping_degraded_us:
            raise ValueError("ping blocked threshold must exceed degraded")
        if self.rtt_blocked_us <= self.rtt_degraded_us:
            raise ValueError("rtt blocked threshold must exceed degraded")
        if (
            self.critical_queue_blocked_depth
            <= self.critical_queue_degraded_depth
        ):
            raise ValueError("critical queue blocked threshold must exceed degraded")


@dataclass(frozen=True, slots=True)
class HealthReason:
    code: str
    state: HealthState
    message: str
    source: str


@dataclass(frozen=True, slots=True)
class SystemHealthSnapshot:
    data: HealthState
    transport: HealthState
    execution: HealthState
    reconciliation: HealthState
    journal: HealthState
    clock: HealthState
    snapshot: HealthState
    overall: HealthState
    reasons: tuple[HealthReason, ...]
    observed_at_ns: int
    healthy_streak: int

    @property
    def healthy(self) -> bool:
        return self.overall is HealthState.OK


class HealthSafetyEngine:
    """Fail-closed Stage-09 health aggregation.

    This component owns only system health classification and the Core HEALTH
    readiness signal. It does not arm execution, approve risk, size positions,
    or submit broker orders.
    """

    DIMENSIONS = (
        "data",
        "transport",
        "execution",
        "reconciliation",
        "journal",
        "clock",
        "snapshot",
    )

    def __init__(self, policy: HealthPolicy | None = None) -> None:
        self.policy = policy or HealthPolicy()
        self._explicit: dict[str, HealthState] = {
            name: HealthState.UNKNOWN for name in self.DIMENSIONS
        }
        self._last_health_event_ns: int | None = None
        self._last_heartbeat_ns: int | None = None
        self._heartbeat: Mapping[str, Any] | None = None
        self._session: Mapping[str, Any] | None = None
        self._metrics: Mapping[str, Any] | None = None
        self._data_fresh: bool | None = None
        self._last_decode_errors: int | None = None
        self._last_decode_error_increase_ns: int | None = None
        self._healthy_event_streak = 0

    @property
    def healthy_event_streak(self) -> int:
        return self._healthy_event_streak

    def observe_health_event(
        self,
        payload: Mapping[str, Any],
        *,
        observed_at_ns: int,
    ) -> None:
        mapping = {
            "data": "data_health",
            "transport": "transport_health",
            "execution": "execution_health",
            "reconciliation": "reconciliation_health",
            "journal": "journal_health",
            "clock": "clock_health",
            "snapshot": "snapshot_health",
        }
        states: dict[str, HealthState] = {}
        for dimension, field in mapping.items():
            value = payload.get(field)
            if not isinstance(value, int) or isinstance(value, bool) or value not in {0, 1, 2, 3}:
                states[dimension] = HealthState.BLOCKED
            else:
                states[dimension] = HealthState(value)

        self._explicit.update(states)
        self._last_health_event_ns = observed_at_ns
        if all(state is HealthState.OK for state in states.values()):
            self._healthy_event_streak += 1
        else:
            self._healthy_event_streak = 0

    def observe_heartbeat(
        self,
        payload: Mapping[str, Any],
        *,
        observed_at_ns: int,
    ) -> None:
        self._heartbeat = dict(payload)
        self._last_heartbeat_ns = observed_at_ns

    def observe_session_state(self, payload: Mapping[str, Any]) -> None:
        self._session = dict(payload)

    def observe_transport_metrics(
        self,
        payload: Mapping[str, Any],
        *,
        observed_at_ns: int,
    ) -> None:
        metrics = dict(payload)
        decode_errors = metrics.get("decode_errors")
        if isinstance(decode_errors, int) and not isinstance(decode_errors, bool):
            if (
                self._last_decode_errors is not None
                and decode_errors > self._last_decode_errors
            ):
                self._last_decode_error_increase_ns = observed_at_ns
            self._last_decode_errors = decode_errors
        self._metrics = metrics

    def observe_data_fresh(self, value: bool) -> None:
        self._data_fresh = bool(value)

    def evaluate(self, *, now_ns: int) -> SystemHealthSnapshot:
        states = dict(self._explicit)
        reasons: list[HealthReason] = []

        if self._last_health_event_ns is None:
            reasons.append(
                self._reason(
                    "HEALTH_EVENT_MISSING",
                    HealthState.UNKNOWN,
                    "authoritative HEALTH_EVENT has not been observed",
                    "health_event",
                )
            )
        elif now_ns - self._last_health_event_ns > self.policy.health_event_stale_ns:
            states["transport"] = self._worse(
                states["transport"], HealthState.BLOCKED
            )
            reasons.append(
                self._reason(
                    "HEALTH_EVENT_STALE",
                    HealthState.BLOCKED,
                    "authoritative HEALTH_EVENT is stale",
                    "health_event",
                )
            )

        if self._last_heartbeat_ns is None:
            states["transport"] = self._worse(
                states["transport"], HealthState.UNKNOWN
            )
            reasons.append(
                self._reason(
                    "HEARTBEAT_MISSING",
                    HealthState.UNKNOWN,
                    "heartbeat has not been observed",
                    "heartbeat",
                )
            )
        else:
            heartbeat_age = now_ns - self._last_heartbeat_ns
            if heartbeat_age > self.policy.heartbeat_stale_ns:
                states["transport"] = self._worse(
                    states["transport"], HealthState.BLOCKED
                )
                reasons.append(
                    self._reason(
                        "HEARTBEAT_STALE",
                        HealthState.BLOCKED,
                        "heartbeat age exceeds safety budget",
                        "heartbeat",
                    )
                )
            self._apply_heartbeat(states, reasons, now_ns)

        if self._session is not None:
            self._apply_session(states, reasons, now_ns)

        if self._metrics is not None:
            self._apply_metrics(states, reasons, now_ns)

        if self._data_fresh is False:
            states["data"] = self._worse(states["data"], HealthState.BLOCKED)
            reasons.append(
                self._reason(
                    "DATA_NOT_FRESH",
                    HealthState.BLOCKED,
                    "Stage-08 data freshness is false",
                    "stage08",
                )
            )
        elif self._data_fresh is None:
            states["data"] = self._worse(states["data"], HealthState.UNKNOWN)

        overall = self._overall(states.values())
        return SystemHealthSnapshot(
            data=states["data"],
            transport=states["transport"],
            execution=states["execution"],
            reconciliation=states["reconciliation"],
            journal=states["journal"],
            clock=states["clock"],
            snapshot=states["snapshot"],
            overall=overall,
            reasons=tuple(reasons),
            observed_at_ns=now_ns,
            healthy_streak=self._healthy_event_streak,
        )

    def apply_readiness(
        self,
        readiness: ReadinessGate,
        *,
        now_ns: int,
    ) -> SystemHealthSnapshot:
        snapshot = self.evaluate(now_ns=now_ns)
        ready = (
            snapshot.overall is HealthState.OK
            and self._healthy_event_streak >= self.policy.healthy_streak_required
        )
        readiness.set(ReadinessSignal.HEALTH, ready)
        return snapshot

    def _apply_heartbeat(
        self,
        states: dict[str, HealthState],
        reasons: list[HealthReason],
        now_ns: int,
    ) -> None:
        assert self._heartbeat is not None
        critical = self._int(self._heartbeat.get("critical_queue_depth"))
        market = self._int(self._heartbeat.get("market_queue_depth"))
        broker_ns = self._int(self._heartbeat.get("last_broker_observation_ns"))

        if critical is not None:
            if critical >= self.policy.critical_queue_blocked_depth:
                states["transport"] = self._worse(
                    states["transport"], HealthState.BLOCKED
                )
                reasons.append(
                    self._reason(
                        "CRITICAL_QUEUE_FULL",
                        HealthState.BLOCKED,
                        "critical queue reached frozen capacity",
                        "heartbeat",
                    )
                )
            elif critical >= self.policy.critical_queue_degraded_depth:
                states["transport"] = self._worse(
                    states["transport"], HealthState.DEGRADED
                )
                reasons.append(
                    self._reason(
                        "CRITICAL_QUEUE_PRESSURE",
                        HealthState.DEGRADED,
                        "critical queue is near capacity",
                        "heartbeat",
                    )
                )

        if (
            market is not None
            and market >= self.policy.market_queue_degraded_depth
        ):
            states["transport"] = self._worse(
                states["transport"], HealthState.DEGRADED
            )
            reasons.append(
                self._reason(
                    "MARKET_QUEUE_PRESSURE",
                    HealthState.DEGRADED,
                    "market queue pressure exceeds policy threshold",
                    "heartbeat",
                )
            )

        if broker_ns is not None and broker_ns > 0:
            if now_ns - broker_ns > self.policy.broker_observation_stale_ns:
                states["data"] = self._worse(
                    states["data"], HealthState.BLOCKED
                )
                reasons.append(
                    self._reason(
                        "BROKER_OBSERVATION_STALE",
                        HealthState.BLOCKED,
                        "last broker observation is stale",
                        "heartbeat",
                    )
                )

    def _apply_session(
        self,
        states: dict[str, HealthState],
        reasons: list[HealthReason],
        now_ns: int,
    ) -> None:
        assert self._session is not None
        connected = self._bool01(self._session.get("terminal_connected"))
        session_open = self._bool01(self._session.get("session_open"))
        fresh_tick = self._bool01(self._session.get("fresh_tick"))
        ping_us = self._int(self._session.get("terminal_ping_us"))
        server_time_ns = self._int(self._session.get("server_time_ns"))

        if connected is False:
            states["transport"] = self._worse(
                states["transport"], HealthState.BLOCKED
            )
            states["execution"] = self._worse(
                states["execution"], HealthState.BLOCKED
            )
            reasons.append(
                self._reason(
                    "TERMINAL_DISCONNECTED",
                    HealthState.BLOCKED,
                    "MT5 terminal is disconnected",
                    "session",
                )
            )

        if session_open is True and fresh_tick is False:
            states["data"] = self._worse(states["data"], HealthState.DEGRADED)
            reasons.append(
                self._reason(
                    "SESSION_OPEN_WITHOUT_FRESH_TICK",
                    HealthState.DEGRADED,
                    "open session does not have a fresh tick",
                    "session",
                )
            )

        if session_open is True:
            permissions = (
                self._bool01(self._session.get("terminal_trade_allowed")),
                self._bool01(self._session.get("mql_trade_allowed")),
                self._bool01(self._session.get("symbol_trade_allowed")),
            )
            if False in permissions:
                states["execution"] = self._worse(
                    states["execution"], HealthState.BLOCKED
                )
                reasons.append(
                    self._reason(
                        "TRADE_PERMISSION_BLOCKED",
                        HealthState.BLOCKED,
                        "open session lacks required terminal/MQL/symbol permission",
                        "session",
                    )
                )

        if ping_us is not None:
            if ping_us >= self.policy.ping_blocked_us:
                states["transport"] = self._worse(
                    states["transport"], HealthState.BLOCKED
                )
                reasons.append(
                    self._reason(
                        "PING_BLOCKED",
                        HealthState.BLOCKED,
                        "terminal ping exceeds blocked threshold",
                        "session",
                    )
                )
            elif ping_us >= self.policy.ping_degraded_us:
                states["transport"] = self._worse(
                    states["transport"], HealthState.DEGRADED
                )
                reasons.append(
                    self._reason(
                        "PING_DEGRADED",
                        HealthState.DEGRADED,
                        "terminal ping exceeds degraded threshold",
                        "session",
                    )
                )

        if server_time_ns is not None and server_time_ns > 0:
            skew = abs(now_ns - server_time_ns)
            if skew >= self.policy.clock_blocked_skew_ns:
                states["clock"] = self._worse(
                    states["clock"], HealthState.BLOCKED
                )
                reasons.append(
                    self._reason(
                        "CLOCK_SKEW_BLOCKED",
                        HealthState.BLOCKED,
                        "server/local clock skew exceeds blocked threshold",
                        "session",
                    )
                )
            elif skew >= self.policy.clock_degraded_skew_ns:
                states["clock"] = self._worse(
                    states["clock"], HealthState.DEGRADED
                )
                reasons.append(
                    self._reason(
                        "CLOCK_SKEW_DEGRADED",
                        HealthState.DEGRADED,
                        "server/local clock skew exceeds degraded threshold",
                        "session",
                    )
                )

    def _apply_metrics(
        self,
        states: dict[str, HealthState],
        reasons: list[HealthReason],
        now_ns: int,
    ) -> None:
        assert self._metrics is not None
        rtt = self._int(self._metrics.get("rtt_us_p99"))
        if rtt is not None:
            if rtt >= self.policy.rtt_blocked_us:
                states["transport"] = self._worse(
                    states["transport"], HealthState.BLOCKED
                )
                reasons.append(
                    self._reason(
                        "RTT_BLOCKED",
                        HealthState.BLOCKED,
                        "transport p99 RTT exceeds blocked threshold",
                        "transport_metrics",
                    )
                )
            elif rtt >= self.policy.rtt_degraded_us:
                states["transport"] = self._worse(
                    states["transport"], HealthState.DEGRADED
                )
                reasons.append(
                    self._reason(
                        "RTT_DEGRADED",
                        HealthState.DEGRADED,
                        "transport p99 RTT exceeds degraded threshold",
                        "transport_metrics",
                    )
                )

        if (
            self._last_decode_error_increase_ns is not None
            and now_ns - self._last_decode_error_increase_ns
            <= self.policy.decode_error_hold_ns
        ):
            states["transport"] = self._worse(
                states["transport"], HealthState.DEGRADED
            )
            reasons.append(
                self._reason(
                    "RECENT_DECODE_ERROR",
                    HealthState.DEGRADED,
                    "transport decode error counter increased recently",
                    "transport_metrics",
                )
            )

    @staticmethod
    def _reason(
        code: str,
        state: HealthState,
        message: str,
        source: str,
    ) -> HealthReason:
        return HealthReason(code=code, state=state, message=message, source=source)

    @staticmethod
    def _int(value: Any) -> int | None:
        return value if isinstance(value, int) and not isinstance(value, bool) else None

    @staticmethod
    def _bool01(value: Any) -> bool | None:
        if value in {0, 1} and not isinstance(value, bool):
            return bool(value)
        if isinstance(value, bool):
            return value
        return None

    @staticmethod
    def _worse(left: HealthState, right: HealthState) -> HealthState:
        rank = {
            HealthState.OK: 0,
            HealthState.UNKNOWN: 1,
            HealthState.DEGRADED: 2,
            HealthState.BLOCKED: 3,
        }
        return left if rank[left] >= rank[right] else right

    @classmethod
    def _overall(cls, states) -> HealthState:
        result = HealthState.OK
        for state in states:
            result = cls._worse(result, state)
        return result
