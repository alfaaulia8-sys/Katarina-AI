from __future__ import annotations

import asyncio
from dataclasses import dataclass

from katarina.ports.transport import (
    ReceivedTransportFrame,
    TransportBackpressureError,
    TransportClosedError,
    TransportPeer,
    TransportState,
)


@dataclass(slots=True)
class _MemoryLink:
    queue: asyncio.Queue[ReceivedTransportFrame | None]


class MemoryTransportEndpoint:
    """Bounded in-memory TransportPort implementation for Stage-07 tests."""

    def __init__(
        self,
        *,
        incoming: _MemoryLink,
        outgoing: _MemoryLink,
        local_peer: TransportPeer,
    ) -> None:
        self._incoming = incoming
        self._outgoing = outgoing
        self._local_peer = local_peer
        self._state = TransportState.STOPPED

    @property
    def state(self) -> TransportState:
        return self._state

    async def start(self) -> None:
        if self._state is TransportState.FAULTED:
            raise TransportClosedError("faulted memory transport cannot restart")
        self._state = TransportState.CONNECTED

    async def stop(self) -> None:
        if self._state is TransportState.STOPPED:
            return
        self._state = TransportState.STOPPED
        try:
            self._incoming.queue.put_nowait(None)
        except asyncio.QueueFull:
            pass

    async def send_frame(
        self,
        frame: bytes,
        *,
        peer: TransportPeer | None = None,
    ) -> None:
        if self._state is not TransportState.CONNECTED:
            raise TransportClosedError("transport is not connected")
        if not frame:
            raise ValueError("frame must be non-empty")

        item = ReceivedTransportFrame(frame=bytes(frame), peer=self._local_peer)
        try:
            self._outgoing.queue.put_nowait(item)
        except asyncio.QueueFull as exc:
            raise TransportBackpressureError(
                "bounded memory transport queue is full"
            ) from exc

    async def receive_frame(self) -> ReceivedTransportFrame:
        if self._state is not TransportState.CONNECTED:
            raise TransportClosedError("transport is not connected")

        item = await self._incoming.queue.get()
        if item is None:
            raise TransportClosedError("transport stopped")
        return item


def create_memory_transport_pair(
    *,
    capacity: int = 64,
    left_peer: TransportPeer | None = None,
    right_peer: TransportPeer | None = None,
) -> tuple[MemoryTransportEndpoint, MemoryTransportEndpoint]:
    if capacity <= 0:
        raise ValueError("capacity must be positive")

    left_in = _MemoryLink(asyncio.Queue(maxsize=capacity))
    right_in = _MemoryLink(asyncio.Queue(maxsize=capacity))

    left = MemoryTransportEndpoint(
        incoming=left_in,
        outgoing=right_in,
        local_peer=left_peer or TransportPeer(route_id=b"left"),
    )
    right = MemoryTransportEndpoint(
        incoming=right_in,
        outgoing=left_in,
        local_peer=right_peer or TransportPeer(route_id=b"right"),
    )
    return left, right
