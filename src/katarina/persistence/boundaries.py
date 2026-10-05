from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from katarina.contracts.runtime import EventEnvelope, MessagePriority


class PersistenceLane(str, Enum):
    """Stage-10 persistence boundary.

    Lanes define storage semantics only. None of them may arm execution,
    approve risk, or bypass readiness/reconciliation.
    """

    TRANSIENT = "transient"
    EVENT_JOURNAL = "event_journal"
    OPERATIONAL_SNAPSHOT = "operational_snapshot"
    EXPERIENCE_MEMORY = "experience_memory"


@dataclass(frozen=True, slots=True)
class BoundaryPolicy:
    lane: PersistenceLane
    append_only: bool
    deterministic_id_required: bool
    rebuildable: bool
    recovery_authority: bool
    live_execution_authority: bool = False

    def __post_init__(self) -> None:
        if self.live_execution_authority:
            raise ValueError(
                "Stage-10 persistence must never grant live execution authority"
            )
        if self.lane is PersistenceLane.EVENT_JOURNAL and not self.append_only:
            raise ValueError("event journal must be append-only")
        if self.lane is PersistenceLane.EXPERIENCE_MEMORY and not self.append_only:
            raise ValueError("experience memory must be append-only in V1")
        if self.recovery_authority and self.lane is not PersistenceLane.EVENT_JOURNAL:
            raise ValueError("only the durable event journal may be recovery-authoritative")


TRANSIENT_POLICY = BoundaryPolicy(
    lane=PersistenceLane.TRANSIENT,
    append_only=False,
    deterministic_id_required=False,
    rebuildable=True,
    recovery_authority=False,
)

EVENT_JOURNAL_POLICY = BoundaryPolicy(
    lane=PersistenceLane.EVENT_JOURNAL,
    append_only=True,
    deterministic_id_required=True,
    rebuildable=False,
    recovery_authority=True,
)

OPERATIONAL_SNAPSHOT_POLICY = BoundaryPolicy(
    lane=PersistenceLane.OPERATIONAL_SNAPSHOT,
    append_only=False,
    deterministic_id_required=False,
    rebuildable=True,
    recovery_authority=False,
)

EXPERIENCE_MEMORY_POLICY = BoundaryPolicy(
    lane=PersistenceLane.EXPERIENCE_MEMORY,
    append_only=True,
    deterministic_id_required=True,
    rebuildable=True,
    recovery_authority=False,
)


_DURABLE_PREFIXES = (
    "decision.",
    "execution.",
    "order.",
    "position.",
    "risk.",
    "health.",
    "reconcile.",
    "account.",
)

_SNAPSHOT_PREFIXES = (
    "snapshot.",
    "state.snapshot.",
)

_EXPERIENCE_PREFIXES = (
    "experience.",
    "memory.experience.",
)

_TRANSIENT_TOPICS = {
    "market.tick",
    "market.bar",
    "transport.metrics",
    "transport.heartbeat",
    "heartbeat",
}


def classify_persistence(event: EventEnvelope) -> BoundaryPolicy:
    """Return the Stage-10 storage lane for an internal event.

    Safety-critical priority always wins over topic naming. This keeps unknown
    CRITICAL/RISK_STATE events durable and fail-closed instead of silently
    dropping them.

    High-frequency market/transport telemetry stays transient by default.
    Later stages may promote selected observations by emitting an explicit
    durable decision/risk/execution evidence event.
    """

    if event.priority <= MessagePriority.RISK_STATE:
        return EVENT_JOURNAL_POLICY

    topic = event.topic.lower()

    if topic.startswith(_EXPERIENCE_PREFIXES):
        return EXPERIENCE_MEMORY_POLICY

    if topic.startswith(_SNAPSHOT_PREFIXES):
        return OPERATIONAL_SNAPSHOT_POLICY

    if topic.startswith(_DURABLE_PREFIXES):
        return EVENT_JOURNAL_POLICY

    if topic in _TRANSIENT_TOPICS:
        return TRANSIENT_POLICY

    return TRANSIENT_POLICY


__all__ = (
    "BoundaryPolicy",
    "PersistenceLane",
    "TRANSIENT_POLICY",
    "EVENT_JOURNAL_POLICY",
    "OPERATIONAL_SNAPSHOT_POLICY",
    "EXPERIENCE_MEMORY_POLICY",
    "classify_persistence",
)
