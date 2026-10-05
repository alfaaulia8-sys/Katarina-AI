from __future__ import annotations

import sqlite3
import tempfile
import unittest
from pathlib import Path

from katarina.contracts.runtime import EventEnvelope, MessagePriority
from katarina.persistence import (
    CanonicalizationError,
    DuplicateRecordError,
    DurableRecord,
    NonDurableEventError,
    PersistenceLane,
    SQLiteAppendOnlyJournal,
    WrongJournalLaneError,
)


class Stage10DurableRecordTests(unittest.TestCase):
    def event(
        self,
        *,
        topic: str = "execution.reported",
        payload=None,
        priority: MessagePriority = MessagePriority.CRITICAL,
        sequence: int | None = 7,
    ) -> EventEnvelope:
        return EventEnvelope(
            topic=topic,
            payload={"b": 2, "a": 1} if payload is None else payload,
            priority=priority,
            sequence=sequence,
            source_time_ns=2_000_000_000_000_000_000,
            trace_id="trace-001",
            source="stage10-test",
        )

    def test_same_semantic_event_has_same_deterministic_id(self):
        left = DurableRecord.from_event(self.event(payload={"b": 2, "a": 1}))
        right = DurableRecord.from_event(self.event(payload={"a": 1, "b": 2}))
        self.assertEqual(left.record_id, right.record_id)
        self.assertEqual(left.payload_json, right.payload_json)
        self.assertEqual(len(left.record_id), 64)

    def test_changed_sequence_changes_record_id(self):
        left = DurableRecord.from_event(self.event(sequence=7))
        right = DurableRecord.from_event(self.event(sequence=8))
        self.assertNotEqual(left.record_id, right.record_id)

    def test_changed_payload_changes_record_id(self):
        left = DurableRecord.from_event(self.event(payload={"value": 1}))
        right = DurableRecord.from_event(self.event(payload={"value": 2}))
        self.assertNotEqual(left.record_id, right.record_id)

    def test_bytes_have_stable_tagged_representation(self):
        record = DurableRecord.from_event(
            self.event(payload={"request_id": bytes.fromhex("0011aaff")})
        )
        self.assertIn('"$bytes_hex":"0011aaff"', record.payload_json)

    def test_float_payload_is_rejected(self):
        with self.assertRaises(CanonicalizationError):
            DurableRecord.from_event(
                self.event(payload={"price": 1.25})
            )

    def test_transient_market_event_cannot_become_durable_record(self):
        with self.assertRaises(NonDurableEventError):
            DurableRecord.from_event(
                self.event(
                    topic="market.tick",
                    priority=MessagePriority.MARKET,
                )
            )


class Stage10SQLiteAppendOnlyJournalTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.db = Path(self.tmp.name) / "stage10.db"
        self.journal = SQLiteAppendOnlyJournal(self.db)

    def tearDown(self) -> None:
        self.journal.close()
        self.tmp.cleanup()

    @staticmethod
    def record(sequence: int = 1) -> DurableRecord:
        return DurableRecord.from_event(
            EventEnvelope(
                topic="execution.reported",
                payload={"ticket": 1000 + sequence, "status": "filled"},
                priority=MessagePriority.CRITICAL,
                sequence=sequence,
                source_time_ns=2_000_000_000_000_000_000 + sequence,
                trace_id=f"trace-{sequence}",
                source="mt5",
            )
        )

    def test_wal_full_and_busy_timeout_are_enforced(self):
        settings = self.journal.settings()
        self.assertEqual(settings["journal_mode"], "wal")
        self.assertEqual(settings["synchronous"], 2)
        self.assertEqual(settings["busy_timeout_ms"], 5000)

    def test_append_and_get_roundtrip(self):
        record = self.record(1)
        stored = self.journal.append(
            record,
            committed_at_ns=2_100_000_000_000_000_001,
        )
        self.assertEqual(stored.ordinal, 1)
        loaded = self.journal.get(record.record_id)
        self.assertIsNotNone(loaded)
        assert loaded is not None
        self.assertEqual(loaded.record, record)
        self.assertEqual(
            loaded.committed_at_ns,
            2_100_000_000_000_000_001,
        )

    def test_ordinals_are_monotonic_and_scan_is_ordered(self):
        first = self.journal.append(self.record(1), committed_at_ns=11)
        second = self.journal.append(self.record(2), committed_at_ns=12)
        third = self.journal.append(self.record(3), committed_at_ns=13)
        self.assertEqual(
            (first.ordinal, second.ordinal, third.ordinal),
            (1, 2, 3),
        )
        scanned = self.journal.scan(after_ordinal=1)
        self.assertEqual(
            [row.record.sequence for row in scanned],
            [2, 3],
        )

    def test_duplicate_record_id_is_rejected_without_overwrite(self):
        record = self.record(1)
        self.journal.append(record, committed_at_ns=11)
        with self.assertRaises(DuplicateRecordError):
            self.journal.append(record, committed_at_ns=99)
        self.assertEqual(self.journal.count(), 1)
        loaded = self.journal.get(record.record_id)
        assert loaded is not None
        self.assertEqual(loaded.committed_at_ns, 11)

    def test_database_trigger_blocks_raw_update(self):
        self.journal.append(self.record(1), committed_at_ns=11)
        external = sqlite3.connect(self.db)
        try:
            with self.assertRaises(sqlite3.DatabaseError):
                external.execute(
                    "UPDATE durable_event_journal "
                    "SET topic='tampered' WHERE ordinal=1"
                )
            external.rollback()
        finally:
            external.close()

    def test_database_trigger_blocks_raw_delete(self):
        self.journal.append(self.record(1), committed_at_ns=11)
        external = sqlite3.connect(self.db)
        try:
            with self.assertRaises(sqlite3.DatabaseError):
                external.execute(
                    "DELETE FROM durable_event_journal WHERE ordinal=1"
                )
            external.rollback()
        finally:
            external.close()

    def test_event_journal_rejects_experience_memory_lane(self):
        record = DurableRecord.from_event(
            EventEnvelope(
                topic="experience.trade_episode",
                payload={"outcome": "win"},
                priority=MessagePriority.ADVISORY,
                sequence=1,
                source_time_ns=100,
                source="evaluation",
            )
        )
        self.assertIs(record.lane, PersistenceLane.EXPERIENCE_MEMORY)
        with self.assertRaises(WrongJournalLaneError):
            self.journal.append(record, committed_at_ns=101)


if __name__ == "__main__":
    unittest.main()
