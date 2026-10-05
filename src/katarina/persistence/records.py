from __future__ import annotations

import hashlib
from dataclasses import dataclass
from typing import Any

from katarina.contracts.runtime import EventEnvelope
from katarina.persistence.boundaries import (
    PersistenceLane,
    classify_persistence,
)
from katarina.persistence.canonical import (
    canonical_json_bytes,
    canonical_json_text,
)


RECORD_SCHEMA_VERSION = 1
_RECORD_DOMAIN = b"KATARINA_DURABLE_RECORD_V1\x00"


class NonDurableEventError(ValueError):
    """Raised when transient/snapshot state is converted to a durable record."""


@dataclass(frozen=True, slots=True)
class DurableRecord:
    record_id: str
    schema_version: int
    lane: PersistenceLane
    topic: str
    priority: int
    payload_json: str
    payload_sha256: str
    source: str
    sequence: int | None
    source_time_ns: int | None
    trace_id: str | None

    def __post_init__(self) -> None:
        if self.schema_version != RECORD_SCHEMA_VERSION:
            raise ValueError("unsupported durable record schema_version")
        if self.lane not in (
            PersistenceLane.EVENT_JOURNAL,
            PersistenceLane.EXPERIENCE_MEMORY,
        ):
            raise ValueError("durable record lane must be append-only")
        if not self.topic:
            raise ValueError("topic must be non-empty")
        if not self.source:
            raise ValueError("source must be non-empty")
        if self.sequence is not None and self.sequence < 0:
            raise ValueError("sequence must be non-negative")
        if self.source_time_ns is not None and self.source_time_ns < 0:
            raise ValueError("source_time_ns must be non-negative")
        if len(self.record_id) != 64:
            raise ValueError("record_id must be a SHA-256 hex digest")
        if len(self.payload_sha256) != 64:
            raise ValueError("payload_sha256 must be a SHA-256 hex digest")

    @classmethod
    def from_event(cls, event: EventEnvelope) -> "DurableRecord":
        policy = classify_persistence(event)
        if policy.lane not in (
            PersistenceLane.EVENT_JOURNAL,
            PersistenceLane.EXPERIENCE_MEMORY,
        ):
            raise NonDurableEventError(
                f"event {event.topic!r} is classified as {policy.lane.value}"
            )

        payload_json = canonical_json_text(event.payload)
        payload_sha256 = hashlib.sha256(
            payload_json.encode("utf-8")
        ).hexdigest()

        identity = {
            "schema_version": RECORD_SCHEMA_VERSION,
            "lane": policy.lane.value,
            "topic": event.topic,
            "priority": int(event.priority),
            "payload": event.payload,
            "source": event.source,
            "sequence": event.sequence,
            "source_time_ns": event.source_time_ns,
            "trace_id": event.trace_id,
        }
        record_id = hashlib.sha256(
            _RECORD_DOMAIN + canonical_json_bytes(identity)
        ).hexdigest()

        return cls(
            record_id=record_id,
            schema_version=RECORD_SCHEMA_VERSION,
            lane=policy.lane,
            topic=event.topic,
            priority=int(event.priority),
            payload_json=payload_json,
            payload_sha256=payload_sha256,
            source=event.source,
            sequence=event.sequence,
            source_time_ns=event.source_time_ns,
            trace_id=event.trace_id,
        )

    def identity_material(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "lane": self.lane.value,
            "topic": self.topic,
            "priority": self.priority,
            "payload_json": self.payload_json,
            "source": self.source,
            "sequence": self.sequence,
            "source_time_ns": self.source_time_ns,
            "trace_id": self.trace_id,
        }


__all__ = (
    "DurableRecord",
    "NonDurableEventError",
    "RECORD_SCHEMA_VERSION",
)
