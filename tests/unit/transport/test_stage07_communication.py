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
    crc32c,
)
from katarina.adapters.transport.memory import create_memory_transport_pair
from katarina.adapters.transport.recovery import (
    Kat1RecoveryGate,
    RecoveryFault,
    RecoveryState,
)
from katarina.adapters.transport.tcp import Kat1TcpServerTransport
from katarina.adapters.transport.zmq import ZmqRouterTransport
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
    TransportClosedError,
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
        semantic_field_alias = {
            "money_scale": "account_currency_digits",
        }

        for vector in self.golden["vectors"]:
            frame = self.codec.decode(bytes.fromhex(vector["hex"]))
            for key, expected in vector["decoded"].items():
                with self.subTest(vector=vector["name"], field=key):
                    wire_key = semantic_field_alias.get(key, key)
                    actual = frame.values[wire_key]
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

    def test_reconcile_len32_records_roundtrip(self) -> None:
        values = {
            "request_id": b"\x10" * 16,
            "snapshot_id": b"\x20" * 16,
            "first_event_cursor": 7,
            "last_event_cursor": 9,
            "position_count": 2,
            "order_count": 1,
            "discrepancy_count": 2,
            "recovery_state": 3,
            "discrepancies": [b"alpha", b"\x00\x01\x02"],
        }
        raw = self.codec.encode(
            message_type=313,
            schema_version=1,
            sequence=10,
            source_time_ns=123,
            stream_id=77,
            boot_id=88,
            values=values,
        )
        frame = self.codec.decode(raw)
        self.assertEqual(frame.values["discrepancies"], values["discrepancies"])
        self.assertEqual(self.codec.reencode(frame), raw)

    def test_reconcile_discrepancy_count_mismatch_rejected(self) -> None:
        values = {
            "request_id": b"\x10" * 16,
            "snapshot_id": b"\x20" * 16,
            "first_event_cursor": 7,
            "last_event_cursor": 9,
            "position_count": 0,
            "order_count": 0,
            "discrepancy_count": 1,
            "recovery_state": 3,
            "discrepancies": [],
        }
        raw = self.codec.encode(
            message_type=313,
            schema_version=1,
            sequence=10,
            source_time_ns=123,
            stream_id=77,
            boot_id=88,
            values=values,
        )
        with self.assertRaises(Kat1ProtocolError):
            self.codec.decode(raw)

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


class Kat1RecoveryGateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.codec = Kat1Codec(SchemaCatalog.from_path(SCHEMA))
        cls.stream_id = 77
        cls.boot_id = 88
        cls.account_id = "11" * 16
        cls.snapshot_id = b"\x33" * 16
        cls.snapshot_request_id = b"\x44" * 16
        cls.reconcile_request_id = b"\x55" * 16

    def _gate(self) -> Kat1RecoveryGate:
        gate = Kat1RecoveryGate(
            codec=self.codec,
            stream_id=self.stream_id,
            boot_id=self.boot_id,
            account_id=self.account_id,
        )
        gate.start(snapshot_request_id=self.snapshot_request_id)
        return gate

    def _snapshot_frames(self, *, bad_chunk_crc: bool = False):
        body = b"abc"
        variable = struct.pack("<HHI", 3, 1, len(body)) + body
        payload_crc = crc32c(variable)
        if bad_chunk_crc:
            payload_crc ^= 1

        begin = self.codec.encode(
            message_type=11,
            schema_version=1,
            sequence=3,
            source_time_ns=2_000,
            stream_id=self.stream_id,
            boot_id=self.boot_id,
            values={
                "snapshot_id": self.snapshot_id,
                "base_sequence": 3,
                "account_revision": 10,
                "expected_chunk_count": 1,
                "expected_record_count": 1,
                "expected_total_payload_bytes": len(variable),
                "record_mask": 0x7F,
                "spec_revision_watermark": 1,
            },
        )
        chunk = self.codec.encode(
            message_type=12,
            schema_version=1,
            sequence=4,
            source_time_ns=2_100,
            stream_id=self.stream_id,
            boot_id=self.boot_id,
            values={
                "snapshot_id": self.snapshot_id,
                "chunk_index": 0,
                "record_count": 1,
                "chunk_payload_bytes": len(variable),
                "payload_crc32c": payload_crc,
                "records": [
                    {
                        "record_type": 3,
                        "schema_version": 1,
                        "body": body,
                    }
                ],
            },
        )
        commit = self.codec.encode(
            message_type=13,
            schema_version=1,
            sequence=5,
            source_time_ns=2_200,
            stream_id=self.stream_id,
            boot_id=self.boot_id,
            values={
                "snapshot_id": self.snapshot_id,
                "chunk_count": 1,
                "record_count": 1,
                "total_payload_bytes": len(variable),
                "aggregate_crc32c": crc32c(variable),
                "sequence_watermark": 5,
                "account_revision": 10,
            },
        )
        return begin, chunk, commit

    def test_atomic_snapshot_and_clean_reconcile_complete_recovery(self) -> None:
        gate = self._gate()
        request = gate.build_snapshot_request(
            sequence=2,
            source_time_ns=1_900,
            requested_record_mask=0x7F,
            after_execution_cursor=0,
        )
        self.assertEqual(self.codec.decode(request).header.message_type, 10)

        for raw in self._snapshot_frames():
            gate.observe_raw(raw)

        self.assertEqual(gate.state, RecoveryState.WAITING_RECONCILE)
        self.assertFalse(gate.communication_ready)
        summary = gate.snapshot_summary
        self.assertIsNotNone(summary)
        self.assertEqual(summary.chunk_count, 1)
        self.assertEqual(summary.record_count, 1)

        reconcile_request = gate.build_reconcile_request(
            sequence=6,
            source_time_ns=2_300,
            request_id=self.reconcile_request_id,
            after_event_cursor=5,
            scope_flags=0xFFFFFFFF,
        )
        self.assertEqual(
            self.codec.decode(reconcile_request).header.message_type,
            312,
        )

        report = self.codec.encode(
            message_type=313,
            schema_version=1,
            sequence=7,
            source_time_ns=2_400,
            stream_id=self.stream_id,
            boot_id=self.boot_id,
            values={
                "request_id": self.reconcile_request_id,
                "snapshot_id": self.snapshot_id,
                "first_event_cursor": 5,
                "last_event_cursor": 5,
                "position_count": 0,
                "order_count": 0,
                "discrepancy_count": 0,
                "recovery_state": 2,
                "discrepancies": [],
            },
        )
        gate.observe_raw(report)
        self.assertEqual(gate.state, RecoveryState.COMPLETE)
        self.assertTrue(gate.communication_ready)
        self.assertFalse(gate.live_risk_ready)

    def test_snapshot_records_are_exposed_only_after_atomic_commit(self) -> None:
        gate = self._gate()
        begin, chunk, commit = self._snapshot_frames()
        gate.observe_raw(begin)
        gate.observe_raw(chunk)
        self.assertEqual(gate.snapshot_records, ())
        gate.observe_raw(commit)
        self.assertEqual(len(gate.snapshot_records), 1)
        self.assertEqual(gate.snapshot_records[0].record_type, 3)
        self.assertEqual(gate.snapshot_records[0].schema_version, 1)
        self.assertEqual(gate.snapshot_records[0].body, b"abc")

    def test_unknown_snapshot_record_type_faults(self) -> None:
        gate = self._gate()
        body = b"abc"
        variable = struct.pack("<HHI", 99, 1, len(body)) + body
        begin = self.codec.encode(
            message_type=11,
            schema_version=1,
            sequence=3,
            source_time_ns=2_000,
            stream_id=self.stream_id,
            boot_id=self.boot_id,
            values={
                "snapshot_id": self.snapshot_id,
                "base_sequence": 3,
                "account_revision": 10,
                "expected_chunk_count": 1,
                "expected_record_count": 1,
                "expected_total_payload_bytes": len(variable),
                "record_mask": 0x7F,
                "spec_revision_watermark": 1,
            },
        )
        chunk = self.codec.encode(
            message_type=12,
            schema_version=1,
            sequence=4,
            source_time_ns=2_100,
            stream_id=self.stream_id,
            boot_id=self.boot_id,
            values={
                "snapshot_id": self.snapshot_id,
                "chunk_index": 0,
                "record_count": 1,
                "chunk_payload_bytes": len(variable),
                "payload_crc32c": crc32c(variable),
                "records": [{
                    "record_type": 99,
                    "schema_version": 1,
                    "body": body,
                }],
            },
        )
        gate.observe_raw(begin)
        with self.assertRaises(RecoveryFault):
            gate.observe_raw(chunk)
        self.assertEqual(gate.state, RecoveryState.FAULTED)

    def test_snapshot_chunk_crc_mismatch_faults(self) -> None:
        gate = self._gate()
        begin, chunk, _ = self._snapshot_frames(bad_chunk_crc=True)
        gate.observe_raw(begin)
        with self.assertRaises(RecoveryFault):
            gate.observe_raw(chunk)
        self.assertEqual(gate.state, RecoveryState.FAULTED)

    def test_snapshot_abort_faults(self) -> None:
        gate = self._gate()
        begin, _, _ = self._snapshot_frames()
        gate.observe_raw(begin)
        abort = self.codec.encode(
            message_type=14,
            schema_version=1,
            sequence=4,
            source_time_ns=2_100,
            stream_id=self.stream_id,
            boot_id=self.boot_id,
            values={
                "snapshot_id": self.snapshot_id,
                "reason_code": 1,
                "failed_chunk_index": 0,
                "related_sequence": 3,
                "message": "synthetic abort",
            },
        )
        with self.assertRaises(RecoveryFault):
            gate.observe_raw(abort)
        self.assertEqual(gate.state, RecoveryState.FAULTED)

    def test_reconcile_discrepancy_blocks_recovery(self) -> None:
        gate = self._gate()
        for raw in self._snapshot_frames():
            gate.observe_raw(raw)
        gate.build_reconcile_request(
            sequence=6,
            source_time_ns=2_300,
            request_id=self.reconcile_request_id,
            after_event_cursor=5,
            scope_flags=0xFFFFFFFF,
        )
        report = self.codec.encode(
            message_type=313,
            schema_version=1,
            sequence=7,
            source_time_ns=2_400,
            stream_id=self.stream_id,
            boot_id=self.boot_id,
            values={
                "request_id": self.reconcile_request_id,
                "snapshot_id": self.snapshot_id,
                "first_event_cursor": 5,
                "last_event_cursor": 6,
                "position_count": 1,
                "order_count": 0,
                "discrepancy_count": 1,
                "recovery_state": 3,
                "discrepancies": [b"position mismatch"],
            },
        )
        with self.assertRaises(RecoveryFault):
            gate.observe_raw(report)
        self.assertEqual(gate.state, RecoveryState.FAULTED)

    def test_session_ready_requires_recovery_gate_completion(self) -> None:
        session = Kat1SessionSupervisor(
            codec=self.codec,
            client_instance_id=b"\xAA" * 16,
            heartbeat_interval_ms=1000,
            stale_after_ms=5000,
        )
        session.start()

        heartbeat = self.codec.encode(
            message_type=HEARTBEAT,
            schema_version=1,
            sequence=1,
            source_time_ns=1_000,
            stream_id=self.stream_id,
            boot_id=self.boot_id,
            values={
                "uptime_ms": 1000,
                "latest_produced_sequence": 1,
                "latest_consumed_command_sequence": 0,
                "critical_queue_depth": 0,
                "market_queue_depth": 0,
                "last_broker_observation_ns": 1_000,
                "transport_state": 1,
            },
        )
        peer = TransportPeer(
            route_id=b"mt5",
            stream_id=self.stream_id,
            boot_id=self.boot_id,
        )
        session.observe(
            ReceivedTransportFrame(frame=heartbeat, peer=peer),
            now_ns=1_000,
        )

        hello_ack = self.codec.encode(
            message_type=HELLO_ACK,
            schema_version=1,
            sequence=2,
            source_time_ns=1_100,
            stream_id=self.stream_id,
            boot_id=self.boot_id,
            values={
                "account_id": bytes.fromhex(self.account_id),
                "broker_login": 123456,
                "terminal_build": 6235,
                "ea_build_version": 700,
                "stream_id": self.stream_id,
                "boot_id_echo": self.boot_id,
                "capability_bits": 0,
                "account_mode": 1,
                "trade_mode": 1,
                "execution_mode": 0,
                "recovery_state": 1,
                "money_scale": 2,
                "account_currency_digits": 2,
                "ea_source_hash": b"\x22" * 32,
                "account_unit_profile_revision": 1,
                "broker_server": "Katarina-CI",
                "account_currency": "USD",
            },
        )
        session.observe(
            ReceivedTransportFrame(frame=hello_ack, peer=peer),
            now_ns=1_100,
        )
        self.assertEqual(session.state, SessionState.RECOVERING)
        self.assertFalse(session.communication_ready)

        gate = self._gate()
        for raw in self._snapshot_frames():
            gate.observe_raw(raw)
        gate.build_reconcile_request(
            sequence=6,
            source_time_ns=2_300,
            request_id=self.reconcile_request_id,
            after_event_cursor=5,
            scope_flags=0xFFFFFFFF,
        )
        report = self.codec.encode(
            message_type=313,
            schema_version=1,
            sequence=7,
            source_time_ns=2_400,
            stream_id=self.stream_id,
            boot_id=self.boot_id,
            values={
                "request_id": self.reconcile_request_id,
                "snapshot_id": self.snapshot_id,
                "first_event_cursor": 5,
                "last_event_cursor": 5,
                "position_count": 0,
                "order_count": 0,
                "discrepancy_count": 0,
                "recovery_state": 2,
                "discrepancies": [],
            },
        )
        gate.observe_raw(report)
        self.assertTrue(gate.communication_ready)

        session.mark_recovered(now_ns=2_500)
        self.assertEqual(session.state, SessionState.READY)
        self.assertTrue(session.communication_ready)
        self.assertFalse(session.live_risk_ready)


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

    def test_python_sequence_starts_above_mt5_consumed_command_floor(self) -> None:
        supervisor = self._supervisor()
        supervisor.start()

        raw = self.codec.encode(
            message_type=HEARTBEAT,
            schema_version=1,
            sequence=50,
            source_time_ns=1_000_000_000,
            stream_id=77,
            boot_id=88,
            values={
                "uptime_ms": 1000,
                "latest_produced_sequence": 50,
                "latest_consumed_command_sequence": 41,
                "critical_queue_depth": 0,
                "market_queue_depth": 0,
                "last_broker_observation_ns": 1_000_000_000,
                "transport_state": 1,
            },
        )
        send = supervisor.observe(
            ReceivedTransportFrame(
                frame=raw,
                peer=TransportPeer(route_id=b"mt5", stream_id=77, boot_id=88),
            ),
            now_ns=1_000_000_000,
        )
        hello = self.codec.decode(send.frame)
        self.assertEqual(hello.header.sequence, 42)

    def test_duplicate_mt5_sequence_faults(self) -> None:
        supervisor = self._supervisor()
        supervisor.start()
        first = self._heartbeat(sequence=1)
        supervisor.observe(first, now_ns=1_000_000_000)

        duplicate = self._heartbeat(
            sequence=1,
            source_time_ns=1_100_000_000,
        )
        with self.assertRaises(SessionFault):
            supervisor.observe(duplicate, now_ns=1_100_000_000)
        self.assertEqual(supervisor.state, SessionState.FAULTED)

    def test_mt5_sequence_gap_faults(self) -> None:
        supervisor = self._supervisor()
        supervisor.start()
        supervisor.observe(
            self._heartbeat(sequence=1),
            now_ns=1_000_000_000,
        )

        gap = self._hello_ack(
            sequence=3,
            source_time_ns=1_100_000_000,
        )
        with self.assertRaises(SessionFault):
            supervisor.observe(gap, now_ns=1_100_000_000)
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


class ZmqRouterTransportTests(unittest.IsolatedAsyncioTestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.codec = Kat1Codec(SchemaCatalog.from_path(SCHEMA))

    def _heartbeat_frame(self) -> bytes:
        return self.codec.encode(
            message_type=HEARTBEAT,
            schema_version=1,
            sequence=1,
            source_time_ns=123456789,
            stream_id=77,
            boot_id=88,
            values={
                "uptime_ms": 1000,
                "latest_produced_sequence": 1,
                "latest_consumed_command_sequence": 0,
                "critical_queue_depth": 0,
                "market_queue_depth": 0,
                "last_broker_observation_ns": 123456789,
                "transport_state": 1,
            },
        )

    async def test_router_dealer_raw_kat1_roundtrip(self) -> None:
        import asyncio
        import socket
        import zmq
        import zmq.asyncio

        probe = socket.socket()
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
        probe.close()

        endpoint = f"tcp://127.0.0.1:{port}"
        router = ZmqRouterTransport(endpoint=endpoint)
        await router.start()
        self.assertEqual(router.state, TransportState.CONNECTED)

        context = zmq.asyncio.Context.instance()
        dealer = context.socket(zmq.DEALER)
        dealer.setsockopt(zmq.IDENTITY, b"mt5-test")
        dealer.setsockopt(zmq.LINGER, 0)
        dealer.connect(endpoint)

        frame = self._heartbeat_frame()
        await dealer.send(frame)

        received = await asyncio.wait_for(
            router.receive_frame(),
            timeout=2.0,
        )
        self.assertEqual(received.frame, frame)
        self.assertEqual(received.peer.route_id, b"mt5-test")

        await router.send_frame(frame, peer=received.peer)
        echoed = await asyncio.wait_for(dealer.recv(), timeout=2.0)
        self.assertEqual(echoed, frame)

        dealer.close(0)
        await router.stop()

    async def test_router_send_requires_route_identity(self) -> None:
        import socket

        probe = socket.socket()
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
        probe.close()

        router = ZmqRouterTransport(
            endpoint=f"tcp://127.0.0.1:{port}",
        )
        await router.start()
        with self.assertRaises(TransportClosedError):
            await router.send_frame(self._heartbeat_frame())
        await router.stop()

    def test_router_rejects_public_bind(self) -> None:
        with self.assertRaises(ValueError):
            ZmqRouterTransport(endpoint="tcp://0.0.0.0:5567")


class TcpTransportTests(unittest.IsolatedAsyncioTestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.codec = Kat1Codec(SchemaCatalog.from_path(SCHEMA))

    def _heartbeat_frame(self) -> bytes:
        return self.codec.encode(
            message_type=HEARTBEAT,
            schema_version=1,
            sequence=1,
            source_time_ns=123456789,
            stream_id=77,
            boot_id=88,
            values={
                "uptime_ms": 1000,
                "latest_produced_sequence": 1,
                "latest_consumed_command_sequence": 0,
                "critical_queue_depth": 0,
                "market_queue_depth": 0,
                "last_broker_observation_ns": 123456789,
                "transport_state": 1,
            },
        )

    async def test_tcp_fallback_frames_fragmented_kat1_stream(self) -> None:
        transport = Kat1TcpServerTransport(port=0, receive_capacity=2)
        await transport.start()
        self.assertEqual(transport.state, TransportState.CONNECTED)
        self.assertIsNotNone(transport.bound_port)

        reader, writer = await __import__("asyncio").open_connection(
            "127.0.0.1",
            transport.bound_port,
        )
        frame = self._heartbeat_frame()

        writer.write(frame[:17])
        await writer.drain()
        writer.write(frame[17:52])
        await writer.drain()
        writer.write(frame[52:])
        await writer.drain()

        received = await __import__("asyncio").wait_for(
            transport.receive_frame(),
            timeout=2.0,
        )
        self.assertEqual(received.frame, frame)
        self.assertIsNotNone(received.peer.route_id)

        await transport.send_frame(frame, peer=received.peer)
        echoed = await __import__("asyncio").wait_for(
            reader.readexactly(len(frame)),
            timeout=2.0,
        )
        self.assertEqual(echoed, frame)

        writer.close()
        await writer.wait_closed()
        await transport.stop()

    async def test_tcp_fallback_requires_route_with_multiple_peers(self) -> None:
        transport = Kat1TcpServerTransport(port=0)
        await transport.start()

        reader1, writer1 = await __import__("asyncio").open_connection(
            "127.0.0.1",
            transport.bound_port,
        )
        reader2, writer2 = await __import__("asyncio").open_connection(
            "127.0.0.1",
            transport.bound_port,
        )
        del reader1, reader2

        for _ in range(20):
            if transport.peer_count == 2:
                break
            await __import__("asyncio").sleep(0.01)

        with self.assertRaises(TransportClosedError):
            await transport.send_frame(self._heartbeat_frame())

        writer1.close()
        writer2.close()
        await writer1.wait_closed()
        await writer2.wait_closed()
        await transport.stop()

    def test_tcp_fallback_rejects_non_loopback_bind(self) -> None:
        with self.assertRaises(ValueError):
            Kat1TcpServerTransport(host="0.0.0.0", port=5000)


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
