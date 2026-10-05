from __future__ import annotations

import sqlite3
import tempfile
import unittest
from pathlib import Path

from katarina.contracts.runtime import EventEnvelope, MessagePriority
from katarina.persistence import (
    APP_ID_EVENT_JOURNAL,
    ApplicationIdError,
    DurableRecord,
    PersistenceBundle,
    SchemaVersionError,
    SQLiteAppendOnlyJournal,
    SQLiteExperienceMemoryStore,
    SQLiteOperationalStateStore,
    StoreError,
    WrongExperienceLaneError,
)


class Stage10SeparatedStoresTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    @staticmethod
    def journal_record(sequence: int = 1) -> DurableRecord:
        return DurableRecord.from_event(
            EventEnvelope(
                topic="execution.reported",
                payload={"ticket": 1000 + sequence, "status": "filled"},
                priority=MessagePriority.CRITICAL,
                sequence=sequence,
                source_time_ns=1000 + sequence,
                source="mt5",
            )
        )

    @staticmethod
    def experience_record(sequence: int = 1) -> DurableRecord:
        return DurableRecord.from_event(
            EventEnvelope(
                topic="experience.trade_episode",
                payload={"episode": sequence, "outcome": "observed"},
                priority=MessagePriority.ADVISORY,
                sequence=sequence,
                source_time_ns=2000 + sequence,
                source="evaluation",
            )
        )

    def test_bundle_uses_three_distinct_database_files(self):
        with PersistenceBundle(self.root) as bundle:
            paths = {
                bundle.journal_path.resolve(),
                bundle.operational_path.resolve(),
                bundle.experience_path.resolve(),
            }
            self.assertEqual(len(paths), 3)
            self.assertTrue(all(path.exists() for path in paths))

    def test_operational_state_is_replaceable(self):
        path = self.root / "operational.sqlite3"
        with SQLiteOperationalStateStore(path) as store:
            first = store.put(
                "runtime",
                {"state": "recovering"},
                source_journal_ordinal=1,
                updated_at_ns=10,
            )
            second = store.put(
                "runtime",
                {"state": "running"},
                source_journal_ordinal=2,
                updated_at_ns=20,
            )
            self.assertNotEqual(first.payload_sha256, second.payload_sha256)
            self.assertEqual(second.source_journal_ordinal, 2)
            self.assertTrue(second.verify_payload())

    def test_operational_state_hash_tamper_fails_closed(self):
        path = self.root / "operational.sqlite3"
        with SQLiteOperationalStateStore(path) as store:
            store.put(
                "runtime",
                {"state": "running"},
                source_journal_ordinal=1,
                updated_at_ns=20,
            )
        conn = sqlite3.connect(path)
        try:
            conn.execute(
                "UPDATE operational_snapshots "
                "SET payload_json='{}' WHERE key='runtime'"
            )
            conn.commit()
        finally:
            conn.close()
        with SQLiteOperationalStateStore(path) as store:
            with self.assertRaises(StoreError):
                store.get("runtime")

    def test_experience_memory_is_append_only(self):
        path = self.root / "experience.sqlite3"
        with SQLiteExperienceMemoryStore(path) as store:
            row = store.append(
                self.experience_record(1),
                committed_at_ns=30,
            )
            self.assertEqual(row.ordinal, 1)

        conn = sqlite3.connect(path)
        try:
            with self.assertRaises(sqlite3.DatabaseError):
                conn.execute(
                    "UPDATE experience_memory SET topic='tampered' "
                    "WHERE ordinal=1"
                )
            conn.rollback()
            with self.assertRaises(sqlite3.DatabaseError):
                conn.execute(
                    "DELETE FROM experience_memory WHERE ordinal=1"
                )
            conn.rollback()
        finally:
            conn.close()

    def test_experience_store_rejects_operational_journal_record(self):
        with SQLiteExperienceMemoryStore(
            self.root / "experience.sqlite3"
        ) as store:
            with self.assertRaises(WrongExperienceLaneError):
                store.append(self.journal_record(1))


class Stage10IdempotencyRecoveryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    @staticmethod
    def journal_record(sequence: int = 1) -> DurableRecord:
        return DurableRecord.from_event(
            EventEnvelope(
                topic="risk.state",
                payload={"revision": sequence, "blocked": True},
                priority=MessagePriority.RISK_STATE,
                sequence=sequence,
                source_time_ns=5000 + sequence,
                source="risk",
            )
        )

    @staticmethod
    def experience_record(sequence: int = 1) -> DurableRecord:
        return DurableRecord.from_event(
            EventEnvelope(
                topic="experience.trade_episode",
                payload={"episode": sequence, "score_ppm": 500000},
                priority=MessagePriority.ADVISORY,
                sequence=sequence,
                source_time_ns=6000 + sequence,
                source="evaluation",
            )
        )

    def test_journal_idempotency_survives_restart(self):
        path = self.root / "journal.sqlite3"
        record = self.journal_record()
        with SQLiteAppendOnlyJournal(path) as journal:
            stored, inserted = journal.append_idempotent(
                record,
                committed_at_ns=100,
            )
            self.assertTrue(inserted)
            self.assertEqual(stored.committed_at_ns, 100)

        with SQLiteAppendOnlyJournal(path) as journal:
            stored, inserted = journal.append_idempotent(
                record,
                committed_at_ns=999,
            )
            self.assertFalse(inserted)
            self.assertEqual(stored.committed_at_ns, 100)
            self.assertEqual(journal.count(), 1)

    def test_experience_idempotency_survives_restart(self):
        path = self.root / "experience.sqlite3"
        record = self.experience_record()
        with SQLiteExperienceMemoryStore(path) as store:
            _, inserted = store.append_idempotent(
                record,
                committed_at_ns=200,
            )
            self.assertTrue(inserted)

        with SQLiteExperienceMemoryStore(path) as store:
            stored, inserted = store.append_idempotent(
                record,
                committed_at_ns=999,
            )
            self.assertFalse(inserted)
            self.assertEqual(stored.committed_at_ns, 200)
            self.assertEqual(store.count(), 1)

    def test_recovery_without_snapshot_replays_full_journal(self):
        with PersistenceBundle(self.root) as bundle:
            bundle.journal.append(self.journal_record(1), committed_at_ns=1)
            plan = bundle.recovery_plan()
            self.assertFalse(plan.snapshot_usable)
            self.assertEqual(plan.replay_after_ordinal, 0)
            self.assertEqual(plan.journal_tail_ordinal, 1)
            self.assertFalse(plan.live_risk_ready)

    def test_valid_snapshot_accelerates_but_does_not_grant_authority(self):
        with PersistenceBundle(self.root) as bundle:
            bundle.journal.append(self.journal_record(1), committed_at_ns=1)
            bundle.journal.append(self.journal_record(2), committed_at_ns=2)
            bundle.operational.put(
                "runtime",
                {"projection": "ok"},
                source_journal_ordinal=1,
                updated_at_ns=3,
            )
            plan = bundle.recovery_plan()
            self.assertTrue(plan.snapshot_usable)
            self.assertEqual(plan.replay_after_ordinal, 1)
            self.assertEqual(plan.journal_tail_ordinal, 2)
            self.assertFalse(plan.live_execution_authority)

    def test_snapshot_ahead_of_journal_fails_closed(self):
        with PersistenceBundle(self.root) as bundle:
            bundle.journal.append(self.journal_record(1), committed_at_ns=1)
            bundle.operational.put(
                "runtime",
                {"projection": "impossible"},
                source_journal_ordinal=99,
                updated_at_ns=3,
            )
            plan = bundle.recovery_plan()
            self.assertFalse(plan.snapshot_usable)
            self.assertEqual(plan.replay_after_ordinal, 0)

    def test_corrupt_snapshot_fails_closed_to_full_replay(self):
        with PersistenceBundle(self.root) as bundle:
            bundle.journal.append(self.journal_record(1), committed_at_ns=1)
            bundle.operational.put(
                "runtime",
                {"projection": "ok"},
                source_journal_ordinal=1,
                updated_at_ns=3,
            )
            operational_path = bundle.operational_path

        conn = sqlite3.connect(operational_path)
        try:
            conn.execute(
                "UPDATE operational_snapshots SET payload_json='{}' "
                "WHERE key='runtime'"
            )
            conn.commit()
        finally:
            conn.close()

        with PersistenceBundle(self.root) as bundle:
            plan = bundle.recovery_plan()
            self.assertFalse(plan.snapshot_usable)
            self.assertEqual(plan.replay_after_ordinal, 0)


class Stage10MigrationIntegrityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_all_three_store_integrity_reports_pass(self):
        with PersistenceBundle(self.root) as bundle:
            report = bundle.integrity_report()
            self.assertTrue(report["all_passed"])
            self.assertTrue(report["journal"]["passed"])
            self.assertTrue(report["operational"]["passed"])
            self.assertTrue(report["experience"]["passed"])

    def test_wrong_application_id_is_rejected(self):
        path = self.root / "wrong.sqlite3"
        conn = sqlite3.connect(path)
        try:
            conn.execute("PRAGMA application_id=123")
        finally:
            conn.close()
        with self.assertRaises(ApplicationIdError):
            SQLiteAppendOnlyJournal(path)

    def test_future_schema_version_is_rejected(self):
        path = self.root / "future.sqlite3"
        conn = sqlite3.connect(path)
        try:
            conn.execute(f"PRAGMA application_id={APP_ID_EVENT_JOURNAL}")
            conn.execute("PRAGMA user_version=99")
        finally:
            conn.close()
        with self.assertRaises(SchemaVersionError):
            SQLiteAppendOnlyJournal(path)


if __name__ == "__main__":
    unittest.main()
