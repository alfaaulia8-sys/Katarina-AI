from __future__ import annotations

import asyncio
import itertools
from dataclasses import dataclass, field

from katarina.contracts.runtime import EventEnvelope


class CriticalIngressOverflow(RuntimeError):
    pass


@dataclass(order=True, slots=True)
class _QueuedEvent:
    priority: int
    ordinal: int
    event: EventEnvelope = field(compare=False)


class IngressQueue:
    """Bounded priority queue with observable non-critical rejection.

    Lossless-required events are never silently dropped.
    """

    def __init__(self, capacity: int) -> None:
        if capacity <= 0:
            raise ValueError("capacity must be positive")
        self._queue: asyncio.PriorityQueue[_QueuedEvent] = asyncio.PriorityQueue(
            maxsize=capacity
        )
        self._ordinal = itertools.count()

    @property
    def capacity(self) -> int:
        return self._queue.maxsize

    def qsize(self) -> int:
        return self._queue.qsize()

    def put_nowait(self, event: EventEnvelope) -> bool:
        item = _QueuedEvent(int(event.priority), next(self._ordinal), event)
        try:
            self._queue.put_nowait(item)
            return True
        except asyncio.QueueFull:
            if event.lossless_required:
                raise CriticalIngressOverflow(
                    "lossless ingress overflow for "
                    f"topic={event.topic} priority={event.priority.name}"
                )
            return False

    async def get(self) -> EventEnvelope:
        return (await self._queue.get()).event

    def get_nowait(self) -> EventEnvelope:
        return self._queue.get_nowait().event
