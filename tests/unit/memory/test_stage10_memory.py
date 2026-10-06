import sqlite3
import tempfile
import unittest
from pathlib import Path

from katarina.memory import IdempotencyConflict, MemoryStore, SchemaVersionError


class Stage10MemoryStoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = Path(self.tmp.name) / "katarina.db"

    def tearDown(self):
        self.tmp.cleanup()

    def test_schema_initializes_and_integrity_is_ok(self):
        with MemoryStore(self.db) as store:
            self.assertEqual(store.schema_version, 1)
            self.assertTrue(store.integrity_check())

    def test_deterministic_id_is_order_independent_for_json_keys(self):
        left = MemoryStore.deterministic_id("x", {"a": 1, "b": 2})
        right = MemoryStore.deterministic_id("x", {"b": 2, "a": 1})
        self.assertEqual(left, right)

    def test_operational_event_is_idempotent(self):
        with MemoryStore(self.db) as store:
            first = store.append_operational_event("heartbeat", {"seq": 7}, event_id="evt-7")
            second = store.append_operational_event("heartbeat", {"seq": 7}, event_id="evt-7")
            self.assertTrue(first.inserted)
            self.assertFalse(second.inserted)
            self.assertEqual(first.sequence, second.sequence)

    def test_operational_id_conflict_fails_closed(self):
        with MemoryStore(self.db) as store:
            store.append_operational_event("heartbeat", {"seq": 7}, event_id="evt-7")
            with self.assertRaises(IdempotencyConflict):
                store.append_operational_event("heartbeat", {"seq": 8}, event_id="evt-7")

    def test_restart_recovery_preserves_order(self):
        with MemoryStore(self.db) as store:
            store.append_operational_event("a", {"v": 1}, event_id="a1")
            store.append_operational_event("b", {"v": 2}, event_id="b1")
        with MemoryStore(self.db) as store:
            rows = store.load_operational_events()
            self.assertEqual([r["event_id"] for r in rows], ["a1", "b1"])
            self.assertEqual([r["sequence"] for r in rows], [1, 2])

    def test_trade_experience_is_separate_from_operational_events(self):
        with MemoryStore(self.db) as store:
            store.append_operational_event("position_closed", {"ticket": 10}, event_id="op-10")
            store.append_trade_experience({"ticket": 10, "r_multiple": 1.25}, experience_id="xp-10")
            self.assertEqual(len(store.load_operational_events()), 1)
            self.assertEqual(len(store.load_trade_experiences()), 1)

    def test_append_only_operational_table_rejects_update_and_delete(self):
        with MemoryStore(self.db) as store:
            store.append_operational_event("a", {"v": 1}, event_id="a1")
            with self.assertRaises(sqlite3.DatabaseError):
                store._conn.execute("UPDATE operational_events SET event_type='x' WHERE event_id='a1'")
            with self.assertRaises(sqlite3.DatabaseError):
                store._conn.execute("DELETE FROM operational_events WHERE event_id='a1'")

    def test_append_only_trade_experience_rejects_update_and_delete(self):
        with MemoryStore(self.db) as store:
            store.append_trade_experience({"ticket": 1}, experience_id="x1")
            with self.assertRaises(sqlite3.DatabaseError):
                store._conn.execute("UPDATE trade_experiences SET closed_utc='x' WHERE experience_id='x1'")
            with self.assertRaises(sqlite3.DatabaseError):
                store._conn.execute("DELETE FROM trade_experiences WHERE experience_id='x1'")

    def test_future_schema_version_is_rejected(self):
        conn = sqlite3.connect(str(self.db))
        conn.execute("CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        conn.execute("INSERT INTO schema_meta(key,value) VALUES('schema_version','99')")
        conn.commit()
        conn.close()
        with self.assertRaises(SchemaVersionError):
            MemoryStore(self.db)


if __name__ == "__main__":
    unittest.main()
