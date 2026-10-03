from __future__ import annotations

import json
import struct
import unittest
from pathlib import Path

from katarina.adapters.transport.kat1_codec import (
    CRITICAL_MESSAGE,
    Kat1Codec,
    Kat1ProtocolError,
    SchemaCatalog,
)
from katarina.adapters.transport.memory import create_memory_transport_pair
from katarina.adapters.transport.session import (
    HELLO,
    HELLO_ACK,
    HEARTBEAT,
    Kat1SessionSupervisor,
    SessionFault,
    SessionState,
)
from katarina.ports.transport import (
    ReceivedTransportFrame,
    TransportBackpressureError,
    TransportPeer,
    TransportPort,
    TransportState,
)


ROOT = Path(__file__).resolve().parents[3]
SCHEMA = ROOT / "protocol" / "kat1_message_schemas_v1.json"
GOLDEN = ROOT / "protocol" / "golden" / "kat1_v1_vectors.json"
ENUMS = ROOT / "protocol" / "enums_v1.json"


class Kat1CodecTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.catalog = SchemaCatalog.from_path(SCHEMA)
        cls.codec = Kat1Codec(cls.catalog)
        cls.golden = json.loads(GOLDEN.read_text(encoding="utf-8"))
        cls.enums = json.loads(ENUMS.read_text(encoding="utf-8"))["enums"]

    def test_all_golden_vectors_decode_and_reencode_exactly(self) -> None:
        for vector in self.golden["vectors"]:
            with self.subTest(vector=vector["name"]):
                raw = bytes.fromhex(vector["hex"])
                frame = self.codec.decode(raw)
                self.assertEqual(frame.header.message_type, vector["message_type"])
                self.assertEqual(frame.header.schema_version, vector["schema_version"])
                self.assertEqual(frame.header.frame_length, vector["frame_length"])
                self.assertEqual(
                    f"{frame.crc32c:08x}",
                    vector["crc32c"],
                )
                self.assertEqual(self.codec.reencode(frame), raw)

    def test_golden_decoded_values_match_fixture_subset(self) -> None:
        enum_alias = {
            "side": "side",
            "entry_type": "entry_type",
            "bar_state": "bar_state",
            "ledger_kind": "ledger_kind",
            "event_kind": "trade_event_kind",
        }

        for vector in self.golden["vectors"]:
            frame = self.codec.decode(bytes.fromhex(vector["hex"]))
            for key, expected in vector["decoded"].items():
                with self.subTest(vector=vector["name"], field=key):
                    actual = frame.values[key]
                    if isinstance(expected, str) and key in enum_alias:
                        enum_name = enum_alias[key]
                        actual = self.enums[enum_name][str(actual)]
                    self.assertEqual(actual, expected)

    def test_bad_magic_rejected(self) -> None:
        raw = bytearray.fromhex(self.golden["vectors"][0]["hex"])
        raw[0] ^= 0xFF
        with self.assertRaises(Kat1ProtocolError):
            self.codec.decode(bytes(raw))

    def test_crc_mismatch_rejected(self) -> None:
        raw = bytearray.fromhex(self.golden["vectors"][0]["hex"])
        raw[60] ^= 0x01
        with self.assertRaises(Kat1ProtocolError):
            self.codec.decode(bytes(raw))

    def test_unknown_flag_rejected(self) -> None:
        raw = bytearray.fromhex(self.golden["vectors"][0]["hex"])
        flags = struct.unpack_from("<H", raw, 14)[0]
        struct.pack_into("<H", raw, 14, flags | 0x8000)
        with self.assertRaises(Kat1ProtocolError):
            self.codec.decode(bytes(raw))

    def test_critical_flag_must_match_schema(self) -> None:
        vector = next(
            item for item in self.golden["vectors"]
            if item["name"] == "TICK_EVENT_XAUUSD"
        )
        frame = self.codec.decode(bytes.fromhex(vector["hex"]))
        with self.assertRaises(Kat1ProtocolError):
            self.codec.encode(
                message_type=frame.header.message_type,
                schema_version=frame.header.schema_version,
                sequence=frame.header.sequence,
                source_time_ns=frame.header.source_time_ns,
                stream_id=frame.header.stream_id,
                boot_id=frame.header.boot_id,
                values=frame.values,
                flags=frame.header.flags | CRITICAL_MESSAGE,
            )


class Kat1SessionSupervisorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.codec = Kat1Codec(SchemaCatalog.from_path(SCHEMA))

    def _heartbeat(
        self,
        *,
        sequence: int = 1,
        stream_id: int = 77,
        boot_id: int = 88,
        source_time_ns: int = 1_000_000_000,
    ) -> ReceivedTransportFrame:
        raw = self.codec.encode(
            message_type=HEARTBEAT,
            schema_version=1,
            sequence=sequence,
            source_time_ns=source_time_ns,
            stream_id=stream_id,
            boot_id=boot_id,
            values={
                "uptime_ms": 1000,
                "latest_produced_sequence": sequence,
                "latest_consumed_command_sequence": 0,
                "critical_queue_depth": 0,
                "market_queue_depth": 0,
                "last_broker_observation_ns": source_time_ns,
                "transport_state": 1,
            },
        )
        return ReceivedTransportFrame(
            frame=raw,
            peer=TransportPeer(
                route_id=b"mt5",
                stream_id=stream_id,
                boot_id=boot_id,
            ),
        )

    def _hello_ack(
        self,
        *,
        sequence: int = 2,
        stream_id: int = 77,
        boot_id: int = 88,
        broker_login: int = 123456,
        broker_server: str = "Broker-Demo",
        account_id: bytes | None = None,
        source_time_ns: int = 1_100_000_000,
    ) -> ReceivedTransportFrame:
        raw = self.codec.encode(
            message_type=HELLO_ACK,
            schema_version=1,
            sequence=sequence,
            source_time_ns=source_time_ns,
            stream_id=stream_id,
            boot_id=boot_id,
            values={
                "account_id": account_id or (b"\x11" * 16),
                "broker_login": broker_login,
                "terminal_build": 6235,
                "ea_build_version": 1000,
                "stream_id": stream_id,
                "boot_id_echo": boot_id,
                "capability_bits": 0,
                "account_mode": 1,
                "trade_mode": 1,
                "execution_mode": 0,
                "recovery_state": 1,
                "money_scale": 2,
                "account_currency_digits": 2,
                "ea_source_hash": b"\x22" * 32,
                "account_unit_profile_revision": 1,
                "broker_server": broker_server,
                "account_currency": "USD",
            },
        )
        return ReceivedTransportFrame(
            frame=raw,
            peer=TransportPeer(
                route_id=b"mt5",
                stream_id=stream_id,
                boot_id=boot_id,
            ),
        )

    def _supervisor(self) -> Kat1SessionSupervisor:
        return Kat1SessionSupervisor(
            codec=self.codec,
            client_instance_id=b"\xAA" * 16,
            heartbeat_interval_ms=1000,
            stale_after_ms=5000,
        )

    def test_presence_emits_read_only_hello_but_never_live_risk_ready(self) -> None:
        supervisor = self._supervisor()
        supervisor.start()

        send = supervisor.observe(
            self._heartbeat(),
            now_ns=1_000_000_000,
        )

        self.assertIsNotNone(send)
        self.assertEqual(supervisor.state, SessionState.HELLO_SENT)
        self.assertFalse(supervisor.communication_ready)
        self.assertFalse(supervisor.live_risk_ready)

        hello = self.codec.decode(send.frame)
        self.assertEqual(hello.header.message_type, HELLO)
        self.assertEqual(hello.header.stream_id, 77)
        self.assertEqual(hello.header.boot_id, 88)
        self.assertEqual(hello.values["requested_execution_mode"], 0)

    def test_hello_ack_requires_explicit_recovery_before_ready(self) -> None:
        supervisor = self._supervisor()
        supervisor.start()
        supervisor.observe(self._heartbeat(), now_ns=1_000_000_000)

        supervisor.observe(
            self._hello_ack(),
            now_ns=1_100_000_000,
        )

        self.assertEqual(supervisor.state, SessionState.RECOVERING)
        self.assertFalse(supervisor.communication_ready)
        self.assertFalse(supervisor.live_risk_ready)
        self.assertEqual(supervisor.binding.broker_login, 123456)

        supervisor.mark_recovered(now_ns=1_200_000_000)
        self.assertEqual(supervisor.state, SessionState.READY)
        self.assertTrue(supervisor.communication_ready)
        self.assertFalse(supervisor.live_risk_ready)

    def test_stale_session_requires_fresh_presence_and_rehandshake(self) -> None:
        supervisor = self._supervisor()
        supervisor.start()
        first_send = supervisor.observe(
            self._heartbeat(),
            now_ns=1_000_000_000,
        )
        first_hello = self.codec.decode(first_send.frame)
        self.assertEqual(first_hello.header.sequence, 1)

        supervisor.observe(
            self._hello_ack(),
            now_ns=1_100_000_000,
        )
        supervisor.mark_recovered(now_ns=1_200_000_000)

        self.assertTrue(
            supervisor.check_stale(now_ns=6_200_000_001)
        )
        self.assertEqual(supervisor.state, SessionState.STALE)
        self.assertFalse(supervisor.communication_ready)

        second_send = supervisor.observe(
            self._heartbeat(sequence=3, source_time_ns=6_300_000_000),
            now_ns=6_300_000_000,
        )
        second_hello = self.codec.decode(second_send.frame)
        self.assertEqual(supervisor.state, SessionState.HELLO_SENT)
        self.assertEqual(second_hello.header.sequence, 2)
        self.assertEqual(second_hello.values["last_known_stream_id"], 77)

        supervisor.observe(
            self._hello_ack(sequence=4, source_time_ns=6_400_000_000),
            now_ns=6_400_000_000,
        )
        self.assertEqual(supervisor.state, SessionState.RECOVERING)

    def test_same_stream_rebinding_to_different_account_faults(self) -> None:
        supervisor = self._supervisor()
        supervisor.start()
        supervisor.observe(self._heartbeat(), now_ns=1_000_000_000)
        supervisor.observe(self._hello_ack(), now_ns=1_100_000_000)
        supervisor.mark_recovered(now_ns=1_200_000_000)
        supervisor.check_stale(now_ns=6_200_000_001)

        supervisor.observe(
            self._heartbeat(sequence=3, source_time_ns=6_300_000_000),
            now_ns=6_300_000_000,
        )
        with self.assertRaises(SessionFault):
            supervisor.observe(
                self._hello_ack(
                    sequence=4,
                    broker_login=999999,
                    source_time_ns=6_400_000_000,
                ),
                now_ns=6_400_000_000,
            )
        self.assertEqual(supervisor.state, SessionState.FAULTED)

    def test_transport_metadata_binding_mismatch_faults(self) -> None:
        supervisor = self._supervisor()
        supervisor.start()
        heartbeat = self._heartbeat()
        bad = ReceivedTransportFrame(
            frame=heartbeat.frame,
            peer=TransportPeer(
                route_id=b"mt5",
                stream_id=999,
                boot_id=88,
            ),
        )
        with self.assertRaises(SessionFault):
            supervisor.observe(bad, now_ns=1_000_000_000)
        self.assertEqual(supervisor.state, SessionState.FAULTED)


class MemoryTransportTests(unittest.IsolatedAsyncioTestCase):
    async def test_memory_pair_implements_transport_port(self) -> None:
        left, right = create_memory_transport_pair(
            capacity=2,
            left_peer=TransportPeer(
                route_id=b"left",
                stream_id=1,
                boot_id=10,
            ),
            right_peer=TransportPeer(
                route_id=b"right",
                stream_id=2,
                boot_id=20,
            ),
        )

        self.assertIsInstance(left, TransportPort)
        self.assertEqual(left.state, TransportState.STOPPED)

        await left.start()
        await right.start()

        await left.send_frame(b"KAT1-test")
        received = await right.receive_frame()
        self.assertEqual(received.frame, b"KAT1-test")
        self.assertEqual(received.peer.stream_id, 1)
        self.assertEqual(received.peer.boot_id, 10)

        await left.stop()
        await right.stop()

    async def test_memory_transport_is_bounded(self) -> None:
        left, right = create_memory_transport_pair(capacity=1)
        await left.start()
        await right.start()

        await left.send_frame(b"first")
        with self.assertRaises(TransportBackpressureError):
            await left.send_frame(b"second")

        received = await right.receive_frame()
        self.assertEqual(received.frame, b"first")

        await left.stop()
        await right.stop()


if __name__ == "__main__":
    unittest.main()
