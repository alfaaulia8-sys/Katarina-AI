from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from katarina.contracts.runtime import RuntimeMode


class ReadinessSignal(str, Enum):
    TRANSPORT = "transport"
    PROTOCOL = "protocol"
    IDENTITY = "identity"
    SNAPSHOT = "snapshot"
    JOURNAL = "journal"
    EVENT_CURSOR = "event_cursor"
    RECONCILED = "reconciled"
    DATA_FRESH = "data_fresh"
    HEALTH = "health"
    RISK = "risk"
    EXECUTION_ARMED = "execution_armed"


_BASE_LIVE = frozenset(
    {
        ReadinessSignal.TRANSPORT,
        ReadinessSignal.PROTOCOL,
        ReadinessSignal.IDENTITY,
        ReadinessSignal.SNAPSHOT,
        ReadinessSignal.JOURNAL,
        ReadinessSignal.EVENT_CURSOR,
        ReadinessSignal.RECONCILED,
    }
)

_REQUIRED_BY_MODE: dict[RuntimeMode, frozenset[ReadinessSignal]] = {
    RuntimeMode.LIVE: _BASE_LIVE,
    RuntimeMode.TESTER: frozenset(
        {
            ReadinessSignal.TRANSPORT,
            ReadinessSignal.PROTOCOL,
            ReadinessSignal.IDENTITY,
            ReadinessSignal.SNAPSHOT,
        }
    ),
}

_LIVE_EXECUTION_REQUIRED = frozenset(
    {
        ReadinessSignal.DATA_FRESH,
        ReadinessSignal.HEALTH,
        ReadinessSignal.RISK,
        ReadinessSignal.EXECUTION_ARMED,
    }
)


@dataclass(frozen=True, slots=True)
class ReadinessSnapshot:
    mode: RuntimeMode
    ready_signals: frozenset[ReadinessSignal]
    core_ready: bool
    live_execution_ready: bool


class ReadinessGate:
    def __init__(self, mode: RuntimeMode) -> None:
        self._mode = mode
        self._signals: dict[ReadinessSignal, bool] = {
            signal: False for signal in ReadinessSignal
        }

    @property
    def mode(self) -> RuntimeMode:
        return self._mode

    def set(self, signal: ReadinessSignal, value: bool) -> None:
        self._signals[signal] = bool(value)

    def reset_live_arming(self) -> None:
        self._signals[ReadinessSignal.EXECUTION_ARMED] = False

    def is_set(self, signal: ReadinessSignal) -> bool:
        return self._signals[signal]

    @property
    def core_ready(self) -> bool:
        return all(
            self._signals[signal] for signal in _REQUIRED_BY_MODE[self._mode]
        )

    @property
    def live_execution_ready(self) -> bool:
        if self._mode is not RuntimeMode.LIVE or not self.core_ready:
            return False
        return all(
            self._signals[signal] for signal in _LIVE_EXECUTION_REQUIRED
        )

    def snapshot(self) -> ReadinessSnapshot:
        ready = frozenset(
            signal for signal, value in self._signals.items() if value
        )
        return ReadinessSnapshot(
            mode=self._mode,
            ready_signals=ready,
            core_ready=self.core_ready,
            live_execution_ready=self.live_execution_ready,
        )
