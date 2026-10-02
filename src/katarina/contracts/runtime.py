from __future__ import annotations

from dataclasses import dataclass
from enum import Enum, IntEnum
from typing import Any


class RuntimeMode(str, Enum):
    LIVE = "live"
    TESTER = "tester"
    SHADOW = "shadow"
    RESEARCH = "research"


class MessagePriority(IntEnum):
    """Lower values are dispatched first."""

    CRITICAL = 0
    RISK_STATE = 5
    MARKET = 20
    ADVISORY = 30


@dataclass(frozen=True, slots=True)
class EventEnvelope:
    """Immutable internal event passed through the Katarina core."""

    topic: str
    payload: Any
    priority: MessagePriority = MessagePriority.MARKET
    sequence: int | None = None
    source_time_ns: int | None = None
    trace_id: str | None = None
    source: str = "internal"

    def __post_init__(self) -> None:
        if not self.topic:
            raise ValueError("topic must be non-empty")
        if self.sequence is not None and self.sequence < 0:
            raise ValueError("sequence must be non-negative")
        if self.source_time_ns is not None and self.source_time_ns < 0:
            raise ValueError("source_time_ns must be non-negative")

    @property
    def lossless_required(self) -> bool:
        return self.priority <= MessagePriority.RISK_STATE
