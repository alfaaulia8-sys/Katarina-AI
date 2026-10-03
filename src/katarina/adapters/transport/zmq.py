from __future__ import annotations

from typing import Any

from katarina.ports.transport import (
    ReceivedTransportFrame,
    TransportBackpressureError,
    TransportClosedError,
    TransportPeer,
    TransportState,
)


class ZmqDependencyError(RuntimeError):
    pass


class ZmqRouterTransport:
    """Stage-07 localhost-only Python ROUTER transport.

    Routing identity is transport metadata only. Complete KAT1 frame bytes are
    the sole application payload.
    """

    def __init__(
        self,
        *,
        endpoint: str = "tcp://127.0.0.1:5567",
        send_hwm: int = 256,
        receive_hwm: int = 256,
    ) -> None:
        if not self._is_loopback_endpoint(endpoint):
            raise ValueError("Stage-07 ZeroMQ ROUTER endpoint must be localhost-only")
        if send_hwm <= 0 or receive_hwm <= 0:
            raise ValueError("ZeroMQ high-water marks must be positive")

        self._endpoint = endpoint
        self._send_hwm = send_hwm
        self._receive_hwm = receive_hwm
        self._state = TransportState.STOPPED
        self._context: Any | None = None
        self._socket: Any | None = None
        self._zmq: Any | None = None

    @property
    def state(self) -> TransportState:
        return self._state

    @property
    def endpoint(self) -> str:
        return self._endpoint

    async def start(self) -> None:
        if self._state is TransportState.FAULTED:
            raise TransportClosedError("faulted ZeroMQ transport cannot restart")
        if self._socket is not None:
            return

        try:
            import zmq
            import zmq.asyncio
        except ImportError as exc:
            raise ZmqDependencyError(
                "pyzmq is required only for the Stage-07 ZeroMQ adapter"
            ) from exc

        self._zmq = zmq
        self._state = TransportState.CONNECTING
        try:
            self._context = zmq.asyncio.Context.instance()
            socket = self._context.socket(zmq.ROUTER)
            socket.setsockopt(zmq.LINGER, 0)
            socket.setsockopt(zmq.SNDHWM, self._send_hwm)
            socket.setsockopt(zmq.RCVHWM, self._receive_hwm)
            socket.setsockopt(zmq.ROUTER_MANDATORY, 1)
            socket.bind(self._endpoint)
            self._socket = socket
            self._state = TransportState.CONNECTED
        except Exception:
            self._state = TransportState.FAULTED
            if self._socket is not None:
                self._socket.close(0)
                self._socket = None
            raise

    async def stop(self) -> None:
        socket = self._socket
        self._socket = None
        if socket is not None:
            socket.close(0)
        self._state = TransportState.STOPPED

    async def send_frame(
        self,
        frame: bytes,
        *,
        peer: TransportPeer | None = None,
    ) -> None:
        if self._state is not TransportState.CONNECTED or self._socket is None:
            raise TransportClosedError("ZeroMQ ROUTER is not connected")
        if not frame:
            raise ValueError("frame must be non-empty")
        if peer is None or not peer.route_id:
            raise TransportClosedError("ROUTER send requires peer route_id")

        try:
            await self._socket.send_multipart(
                [bytes(peer.route_id), bytes(frame)],
                flags=self._zmq.NOBLOCK,
            )
        except self._zmq.Again as exc:
            raise TransportBackpressureError(
                "ZeroMQ ROUTER send high-water mark reached"
            ) from exc
        except self._zmq.ZMQError as exc:
            raise TransportClosedError(
                f"ZeroMQ ROUTER send failed: {exc}"
            ) from exc

    async def receive_frame(self) -> ReceivedTransportFrame:
        if self._state is not TransportState.CONNECTED or self._socket is None:
            raise TransportClosedError("ZeroMQ ROUTER is not connected")

        try:
            parts = await self._socket.recv_multipart()
        except self._zmq.ZMQError as exc:
            raise TransportClosedError(
                f"ZeroMQ ROUTER receive failed: {exc}"
            ) from exc

        if len(parts) != 2:
            self._state = TransportState.FAULTED
            raise TransportClosedError(
                f"ZeroMQ ROUTER expected identity+payload, got {len(parts)} parts"
            )

        route_id, payload = parts
        if not route_id:
            self._state = TransportState.FAULTED
            raise TransportClosedError("ZeroMQ ROUTER received empty route identity")
        if not payload:
            self._state = TransportState.FAULTED
            raise TransportClosedError("ZeroMQ ROUTER received empty application payload")

        return ReceivedTransportFrame(
            frame=bytes(payload),
            peer=TransportPeer(route_id=bytes(route_id)),
        )

    @staticmethod
    def _is_loopback_endpoint(endpoint: str) -> bool:
        lowered = endpoint.strip().lower()
        return (
            lowered.startswith("tcp://127.0.0.1:")
            or lowered.startswith("tcp://localhost:")
            or lowered.startswith("tcp://[::1]:")
        )
