from __future__ import annotations

import sqlite3
import time
from dataclasses import dataclass
from pathlib import Path

from katarina.persistence.boundaries import PersistenceLane
from katarina.persistence.records import DurableRecord
from katarina.persistence.sqlite_common import (
    APP_ID_EVENT_JOURNAL,
    configure_connection,
    ensure_application_id,
    integrity_report as sqlite_integrity_report,
    migrate_v1,
)


class JournalError(RuntimeError):
    pass


class DuplicateRecordError(JournalError):
    pass


class IdempotencyConflictError(JournalError):
    pass


class WrongJournalLaneError(JournalError):
    pass


@dataclass(frozen=True, slots=True)
class StoredJournalRecord:
    ordinal: int
    committed_at_ns: int
    record: DurableRecord


class SQLiteAppendOnlyJournal:
    """Authoritative append-only Event Journal.

    Facts are immutable at the database layer. Schema identity/version and
    durability PRAGMAs are verified on every open.
    """

    _TABLE = "durable_event_journal"

    def __init__(self, path: str | Path, *, busy_timeout_ms: int = 5_000) -> None:
        if busy_timeout_ms <= 0:
            raise ValueError("busy_timeout_ms must be positive")

        self.path = Path(path)
        if self.path != Path(":memory:"):
            self.path.parent.mkdir(parents=True, exist_ok=True)

        self._conn = sqlite3.connect(
            str(self.path),
            timeout=busy_timeout_ms / 1000.0,
            isolation_level=None,
        )
        self._conn.row_factory = sqlite3.Row

        try:
            configure_connection(
                self._conn,
                self.path,
                busy_timeout_ms=busy_timeout_ms,
            )
            ensure_application_id(self._conn, APP_ID_EVENT_JOURNAL)
            migrate_v1(self._conn, create_schema=self._create_schema)
            self._create_schema()
        except Exception:
            self._conn.close()
            raise

    def _create_schema(self) -> None:
        self._conn.executescript(
            f"""
            CREATE TABLE IF NOT EXISTS {self._TABLE} (
                ordinal INTEGER PRIMARY KEY AUTOINCREMENT,
                record_id TEXT NOT NULL UNIQUE,
                schema_version INTEGER NOT NULL
                    CHECK (schema_version = 1),
                lane TEXT NOT NULL
                    CHECK (lane = 'event_journal'),
                topic TEXT NOT NULL,
                priority INTEGER NOT NULL,
                payload_json TEXT NOT NULL,
                payload_sha256 TEXT NOT NULL,
                source TEXT NOT NULL,
                sequence INTEGER,
                source_time_ns INTEGER,
                trace_id TEXT,
                committed_at_ns INTEGER NOT NULL
                    CHECK (committed_at_ns >= 0)
            );

            CREATE INDEX IF NOT EXISTS
                idx_durable_event_journal_topic_ordinal
            ON {self._TABLE}(topic, ordinal);

            CREATE TRIGGER IF NOT EXISTS
                trg_durable_event_journal_no_update
            BEFORE UPDATE ON {self._TABLE}
            BEGIN
                SELECT RAISE(ABORT, 'append-only journal: UPDATE forbidden');
            END;

            CREATE TRIGGER IF NOT EXISTS
                trg_durable_event_journal_no_delete
            BEFORE DELETE ON {self._TABLE}
            BEGIN
                SELECT RAISE(ABORT, 'append-only journal: DELETE forbidden');
            END;
            """
        )

    def close(self) -> None:
        self._conn.close()

    def __enter__(self) -> "SQLiteAppendOnlyJournal":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def append(
        self,
        record: DurableRecord,
        *,
        committed_at_ns: int | None = None,
    ) -> StoredJournalRecord:
        if record.lane is not PersistenceLane.EVENT_JOURNAL:
            raise WrongJournalLaneError(
                "Event Journal accepts only event_journal records"
            )

        commit_ns = time.time_ns() if committed_at_ns is None else committed_at_ns
        if commit_ns < 0:
            raise ValueError("committed_at_ns must be non-negative")

        try:
            self._conn.execute("BEGIN IMMEDIATE")
            cursor = self._conn.execute(
                f"""
                INSERT INTO {self._TABLE} (
                    record_id,
                    schema_version,
                    lane,
                    topic,
                    priority,
                    payload_json,
                    payload_sha256,
                    source,
                    sequence,
                    source_time_ns,
                    trace_id,
                    committed_at_ns
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    record.record_id,
                    record.schema_version,
                    record.lane.value,
                    record.topic,
                    record.priority,
                    record.payload_json,
                    record.payload_sha256,
                    record.source,
                    record.sequence,
                    record.source_time_ns,
                    record.trace_id,
                    commit_ns,
                ),
            )
            ordinal = int(cursor.lastrowid)
            self._conn.execute("COMMIT")
        except sqlite3.IntegrityError as exc:
            self._rollback_quietly()
            if "record_id" in str(exc) or "UNIQUE" in str(exc).upper():
                raise DuplicateRecordError(record.record_id) from exc
            raise JournalError(str(exc)) from exc
        except sqlite3.Error as exc:
            self._rollback_quietly()
            raise JournalError(str(exc)) from exc

        return StoredJournalRecord(
            ordinal=ordinal,
            committed_at_ns=commit_ns,
            record=record,
        )

    def append_idempotent(
        self,
        record: DurableRecord,
        *,
        committed_at_ns: int | None = None,
    ) -> tuple[StoredJournalRecord, bool]:
        """Append once; an exact deterministic replay is safe.

        Returns a pair of stored record and inserted flag. A record-ID
        collision or content mismatch fails closed.
        """

        try:
            return self.append(
                record,
                committed_at_ns=committed_at_ns,
            ), True
        except DuplicateRecordError:
            existing = self.get(record.record_id)
            if existing is None:
                raise IdempotencyConflictError(
                    "duplicate record_id exists but cannot be read"
                )
            if existing.record != record:
                raise IdempotencyConflictError(
                    f"record_id collision/content mismatch: {record.record_id}"
                )
            return existing, False

    def get(self, record_id: str) -> StoredJournalRecord | None:
        row = self._conn.execute(
            f"SELECT * FROM {self._TABLE} WHERE record_id=?",
            (record_id,),
        ).fetchone()
        return None if row is None else self._from_row(row)

    def scan(
        self,
        *,
        after_ordinal: int = 0,
        limit: int = 1_000,
    ) -> tuple[StoredJournalRecord, ...]:
        if after_ordinal < 0:
            raise ValueError("after_ordinal must be non-negative")
        if limit <= 0:
            raise ValueError("limit must be positive")

        rows = self._conn.execute(
            f"""
            SELECT *
            FROM {self._TABLE}
            WHERE ordinal > ?
            ORDER BY ordinal ASC
            LIMIT ?
            """,
            (after_ordinal, limit),
        ).fetchall()
        return tuple(self._from_row(row) for row in rows)

    def count(self) -> int:
        return int(
            self._conn.execute(
                f"SELECT COUNT(*) FROM {self._TABLE}"
            ).fetchone()[0]
        )

    def tail_ordinal(self) -> int:
        value = self._conn.execute(
            f"SELECT COALESCE(MAX(ordinal), 0) FROM {self._TABLE}"
        ).fetchone()[0]
        return int(value)

    def settings(self) -> dict[str, int | str]:
        return {
            "journal_mode": str(
                self._conn.execute("PRAGMA journal_mode").fetchone()[0]
            ).lower(),
            "synchronous": int(
                self._conn.execute("PRAGMA synchronous").fetchone()[0]
            ),
            "busy_timeout_ms": int(
                self._conn.execute("PRAGMA busy_timeout").fetchone()[0]
            ),
            "application_id": int(
                self._conn.execute("PRAGMA application_id").fetchone()[0]
            ),
            "schema_version": int(
                self._conn.execute("PRAGMA user_version").fetchone()[0]
            ),
        }

    def integrity_report(self) -> dict[str, object]:
        return sqlite_integrity_report(
            self._conn,
            expected_application_id=APP_ID_EVENT_JOURNAL,
        )

    def _rollback_quietly(self) -> None:
        try:
            self._conn.execute("ROLLBACK")
        except sqlite3.Error:
            pass

    @staticmethod
    def _from_row(row: sqlite3.Row) -> StoredJournalRecord:
        record = DurableRecord(
            record_id=str(row["record_id"]),
            schema_version=int(row["schema_version"]),
            lane=PersistenceLane(str(row["lane"])),
            topic=str(row["topic"]),
            priority=int(row["priority"]),
            payload_json=str(row["payload_json"]),
            payload_sha256=str(row["payload_sha256"]),
            source=str(row["source"]),
            sequence=(
                None if row["sequence"] is None else int(row["sequence"])
            ),
            source_time_ns=(
                None
                if row["source_time_ns"] is None
                else int(row["source_time_ns"])
            ),
            trace_id=(
                None if row["trace_id"] is None else str(row["trace_id"])
            ),
        )
        return StoredJournalRecord(
            ordinal=int(row["ordinal"]),
            committed_at_ns=int(row["committed_at_ns"]),
            record=record,
        )


__all__ = (
    "DuplicateRecordError",
    "IdempotencyConflictError",
    "JournalError",
    "SQLiteAppendOnlyJournal",
    "StoredJournalRecord",
    "WrongJournalLaneError",
)
