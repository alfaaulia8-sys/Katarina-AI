from __future__ import annotations

import asyncio
import struct
from dataclasses import dataclass

from katarina.adapters.transport.kat1_codec import HEADER_BYTES, MAGIC, MAX_FRAME_BYTES
from katarina.ports.transport import (
    ReceivedTransportFrame,
    TransportClosedError,
    TransportPeer,
    TransportState,
)


@dataclass(slots=True)
class _TcpPeerConnection:
    route_id: bytes
    writer: asyncio.StreamWriter
    task: asyncio.Task[None] | None = None


class Kat1TcpServerTransport:
    """Localhost-only native TCP fallback for complete KAT1 frames.

    The adapter introduces no secondary envelope. Stream framing reads the
    frozen 52-byte KAT1 header, then uses the KAT1 frame_length field.
    """

    def __init__(
        self,
        *,
        host: str = "127.0.0.1",
        port: int = 0,
        receive_capacity: int = 256,
    ) -> None:
        if host not in {"127.0.0.1", "::1", "localhost"}:
            raise ValueError("Stage-07 TCP transport is localhost-only")
        if not 0 <= port <= 65535:
            raise ValueError("port must be between 0 and 65535")
        if receive_capacity <= 0:
            raise ValueError("receive_capacity must be positive")

        self._host = host
        self._requested_port = port
        self._receive_capacity = receive_capacity
        self._incoming: asyncio.Queue[ReceivedTransportFrame | None] = (
            asyncio.Queue(maxsize=receive_capacity)
        )
        self._server: asyncio.AbstractServer | None = None
        self._connections: dict[bytes, _TcpPeerConnection] = {}
        self._connection_counter = 0
        self._state = TransportState.STOPPED
        self._bound_port: int | None = None

    @property
    def state(self) -> TransportState:
        return self._state

    @property
    def bound_port(self) -> int | None:
        return self._bound_port

    @property
    def endpoint(self) -> tuple[str, int] | None:
        if self._bound_port is None:
            return None
        return self._host, self._bound_port

    @property
    def peer_count(self) -> int:
        return len(self._connections)

    async def start(self) -> None:
        if self._state is TransportState.FAULTED:
            raise TransportClosedError("faulted TCP transport cannot restart")
        if self._server is not None:
            return

        self._state = TransportState.CONNECTING
        try:
            self._server = await asyncio.start_server(
                self._on_client,
                host=self._host,
                port=self._requested_port,
            )
        except Exception:
            self._state = TransportState.FAULTED
            raise

        sockets = self._server.sockets or ()
        if not sockets:
            self._state = TransportState.FAULTED
            raise TransportClosedError("TCP server has no bound socket")

        self._bound_port = int(sockets[0].getsockname()[1])
        self._state = TransportState.CONNECTED

    async def stop(self) -> None:
        server = self._server
        self._server = None
        self._bound_port = None

        if server is not None:
            server.close()
            await server.wait_closed()

        connections = list(self._connections.values())
        self._connections.clear()

        current = asyncio.current_task()
        for connection in connections:
            connection.writer.close()
        for connection in connections:
            try:
                await connection.writer.wait_closed()
            except (ConnectionError, OSError):
                pass
            if (
                connection.task is not None
                and connection.task is not current
                and not connection.task.done()
            ):
                connection.task.cancel()

        self._state = TransportState.STOPPED
        try:
            self._incoming.put_nowait(None)
        except asyncio.QueueFull:
            pass

    async def send_frame(
        self,
        frame: bytes,
        *,
        peer: TransportPeer | None = None,
    ) -> None:
        if self._state is not TransportState.CONNECTED:
            raise TransportClosedError("TCP transport is not connected")

        raw = bytes(frame)
        self._validate_frame_shell(raw)

        connection = self._resolve_connection(peer)
        try:
            connection.writer.write(raw)
            await connection.writer.drain()
        except (ConnectionError, OSError) as exc:
            self._connections.pop(connection.route_id, None)
            raise TransportClosedError("TCP peer disconnected during send") from exc

    async def receive_frame(self) -> ReceivedTransportFrame:
        if self._state is not TransportState.CONNECTED:
            raise TransportClosedError("TCP transport is not connected")

        item = await self._incoming.get()
        if item is None:
            raise TransportClosedError("TCP transport stopped")
        return item

    async def _on_client(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ) -> None:
        self._connection_counter += 1
        route_id = f"tcp-{self._connection_counter}".encode("ascii")
        connection = _TcpPeerConnection(route_id=route_id, writer=writer)
        connection.task = asyncio.current_task()
        self._connections[route_id] = connection

        try:
            while self._state is TransportState.CONNECTED:
                header = await reader.readexactly(HEADER_BYTES)
                frame_length = self._frame_length_from_header(header)
                body = await reader.readexactly(frame_length - HEADER_BYTES)
                raw = header + body
                await self._incoming.put(
                    ReceivedTransportFrame(
                        frame=raw,
                        peer=TransportPeer(route_id=route_id),
                    )
                )
        except asyncio.IncompleteReadError:
            pass
        except asyncio.CancelledError:
            raise
        except Exception:
            self._state = TransportState.FAULTED
        finally:
            self._connections.pop(route_id, None)
            writer.close()
            try:
                await writer.wait_closed()
            except (ConnectionError, OSError):
                pass

    def _resolve_connection(
        self,
        peer: TransportPeer | None,
    ) -> _TcpPeerConnection:
        if peer is not None and peer.route_id is not None:
            try:
                return self._connections[peer.route_id]
            except KeyError as exc:
                raise TransportClosedError("unknown TCP route_id") from exc

        if len(self._connections) != 1:
            raise TransportClosedError(
                "peer route_id is required unless exactly one TCP peer is connected"
            )
        return next(iter(self._connections.values()))

    @staticmethod
    def _validate_frame_shell(frame: bytes) -> None:
        if len(frame) < HEADER_BYTES:
            raise ValueError("frame shorter than KAT1 header")
        expected = Kat1TcpServerTransport._frame_length_from_header(
            frame[:HEADER_BYTES]
        )
        if expected != len(frame):
            raise ValueError("KAT1 frame_length does not match frame bytes")

    @staticmethod
    def _frame_length_from_header(header: bytes) -> int:
        if len(header) != HEADER_BYTES:
            raise ValueError("KAT1 TCP header must be exactly 52 bytes")
        if header[:4] != MAGIC:
            raise ValueError("bad KAT1 magic on TCP stream")

        header_length = struct.unpack_from("<H", header, 6)[0]
        if header_length != HEADER_BYTES:
            raise ValueError("invalid KAT1 header_length on TCP stream")

        frame_length = struct.unpack_from("<I", header, 16)[0]
        if frame_length < HEADER_BYTES:
            raise ValueError("invalid KAT1 frame_length on TCP stream")
        if frame_length > MAX_FRAME_BYTES:
            raise ValueError("KAT1 frame exceeds maximum on TCP stream")
        return frame_length
