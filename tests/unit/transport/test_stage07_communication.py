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
from katarina.ports.transport import (
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
