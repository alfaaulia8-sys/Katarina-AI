from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Protocol, runtime_checkable


class TransportState(str, Enum):
    STOPPED = "stopped"
    CONNECTING = "connecting"
    CONNECTED = "connected"
    STALE = "stale"
    FAULTED = "faulted"


@dataclass(frozen=True, slots=True)
class TransportPeer:
    route_id: bytes | None = None
    stream_id: int | None = None
    boot_id: int | None = None

    def __post_init__(self) -> None:
        if self.stream_id is not None and self.stream_id < 0:
            raise ValueError("stream_id must be non-negative")
        if self.boot_id is not None and self.boot_id < 0:
            raise ValueError("boot_id must be non-negative")


@dataclass(frozen=True, slots=True)
class ReceivedTransportFrame:
    frame: bytes
    peer: TransportPeer

    def __post_init__(self) -> None:
        if not self.frame:
            raise ValueError("frame must be non-empty")


class TransportError(RuntimeError):
    pass


class TransportBackpressureError(TransportError):
    pass


class TransportClosedError(TransportError):
    pass


@runtime_checkable
class TransportPort(Protocol):
    """Application-owned byte transport contract.

    Concrete adapters may use ZeroMQ, TCP, memory, or TesterTransport, but
    callers only exchange complete KAT1 frame bytes.
    """

    @property
    def state(self) -> TransportState:
        ...

    async def start(self) -> None:
        ...

    async def stop(self) -> None:
        ...

    async def send_frame(
        self,
        frame: bytes,
        *,
        peer: TransportPeer | None = None,
    ) -> None:
        ...

    async def receive_frame(self) -> ReceivedTransportFrame:
        ...
