from __future__ import annotations

from dataclasses import dataclass

from katarina.contracts.runtime import RuntimeMode
from katarina.core.lifecycle import LifecycleState
from katarina.core.readiness import ReadinessSnapshot


@dataclass(frozen=True, slots=True)
class CoreStatus:
    mode: RuntimeMode
    lifecycle: LifecycleState
    readiness: ReadinessSnapshot
    processed_events: int
    dropped_noncritical_events: int
    last_error: str | None


class RuntimeStateStore:
    """Single-writer orchestration state, not a trading/domain state database."""

    def __init__(self, mode: RuntimeMode) -> None:
        self.mode = mode
        self.processed_events = 0
        self.dropped_noncritical_events = 0
        self.last_error: str | None = None

    def record_processed(self) -> None:
        self.processed_events += 1

    def record_drop(self) -> None:
        self.dropped_noncritical_events += 1

    def record_error(self, message: str) -> None:
        self.last_error = message

    def snapshot(
        self,
        lifecycle: LifecycleState,
        readiness: ReadinessSnapshot,
    ) -> CoreStatus:
        return CoreStatus(
            mode=self.mode,
            lifecycle=lifecycle,
            readiness=readiness,
            processed_events=self.processed_events,
            dropped_noncritical_events=self.dropped_noncritical_events,
            last_error=self.last_error,
        )
