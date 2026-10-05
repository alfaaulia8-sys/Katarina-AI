from __future__ import annotations

import hashlib
import sqlite3
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from katarina.persistence.boundaries import PersistenceLane
from katarina.persistence.canonical import canonical_json_text
from katarina.persistence.records import DurableRecord
from katarina.persistence.sqlite_common import (
    APP_ID_EXPERIENCE_MEMORY,
    APP_ID_OPERATIONAL_STATE,
    configure_connection,
    ensure_application_id,
    integrity_report as sqlite_integrity_report,
    migrate_v1,
)
from katarina.persistence.sqlite_journal import IdempotencyConflictError


class StoreError(RuntimeError):
    pass


class WrongExperienceLaneError(StoreError):
    pass


@dataclass(frozen=True, slots=True)
class OperationalSnapshot:
    key: str
    schema_version: int
    payload_json: str
    payload_sha256: str
    source_journal_ordinal: int
    updated_at_ns: int

    def verify_payload(self) -> bool:
        digest = hashlib.sha256(
            self.payload_json.encode("utf-8")
        ).hexdigest()
        return digest == self.payload_sha256


@dataclass(frozen=True, slots=True)
class StoredExperienceRecord:
    ordinal: int
    committed_at_ns: int
    record: DurableRecord


class SQLiteOperationalStateStore:
    """Replaceable/rebuildable operational state.

    This store is deliberately not authoritative. It may accelerate restart,
    but Event Journal + broker reconciliation remain the source of truth.
    """

    _TABLE = "operational_snapshots"

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
            ensure_application_id(
                self._conn,
                APP_ID_OPERATIONAL_STATE,
            )
            migrate_v1(self._conn, create_schema=self._create_schema)
            self._create_schema()
        except Exception:
            self._conn.close()
            raise

    def _create_schema(self) -> None:
        self._conn.executescript(
            f"""
            CREATE TABLE IF NOT EXISTS {self._TABLE} (
                key TEXT PRIMARY KEY,
                schema_version INTEGER NOT NULL
                    CHECK (schema_version = 1),
                payload_json TEXT NOT NULL,
                payload_sha256 TEXT NOT NULL,
                source_journal_ordinal INTEGER NOT NULL
                    CHECK (source_journal_ordinal >= 0),
                updated_at_ns INTEGER NOT NULL
                    CHECK (updated_at_ns >= 0)
            );
            """
        )

    def put(
        self,
        key: str,
        payload: Any,
        *,
        source_journal_ordinal: int,
        updated_at_ns: int | None = None,
    ) -> OperationalSnapshot:
        if not key:
            raise ValueError("snapshot key must be non-empty")
        if source_journal_ordinal < 0:
            raise ValueError("source_journal_ordinal must be non-negative")
        now_ns = time.time_ns() if updated_at_ns is None else updated_at_ns
        if now_ns < 0:
            raise ValueError("updated_at_ns must be non-negative")

        payload_json = canonical_json_text(payload)
        digest = hashlib.sha256(payload_json.encode("utf-8")).hexdigest()

        try:
            self._conn.execute("BEGIN IMMEDIATE")
            self._conn.execute(
                f"""
                INSERT INTO {self._TABLE} (
                    key,
                    schema_version,
                    payload_json,
                    payload_sha256,
                    source_journal_ordinal,
                    updated_at_ns
                ) VALUES (?, 1, ?, ?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET
                    schema_version=excluded.schema_version,
                    payload_json=excluded.payload_json,
                    payload_sha256=excluded.payload_sha256,
                    source_journal_ordinal=excluded.source_journal_ordinal,
                    updated_at_ns=excluded.updated_at_ns
                """,
                (
                    key,
                    payload_json,
                    digest,
                    source_journal_ordinal,
                    now_ns,
                ),
            )
            self._conn.execute("COMMIT")
        except sqlite3.Error as exc:
            self._rollback_quietly()
            raise StoreError(str(exc)) from exc

        snapshot = self.get(key)
        if snapshot is None:
            raise StoreError("snapshot write committed but row is unavailable")
        return snapshot

    def get(self, key: str) -> OperationalSnapshot | None:
        row = self._conn.execute(
            f"SELECT * FROM {self._TABLE} WHERE key=?",
            (key,),
        ).fetchone()
        if row is None:
            return None
        snapshot = OperationalSnapshot(
            key=str(row["key"]),
            schema_version=int(row["schema_version"]),
            payload_json=str(row["payload_json"]),
            payload_sha256=str(row["payload_sha256"]),
            source_journal_ordinal=int(row["source_journal_ordinal"]),
            updated_at_ns=int(row["updated_at_ns"]),
        )
        if not snapshot.verify_payload():
            raise StoreError(
                f"operational snapshot payload hash mismatch: {snapshot.key}"
            )
        return snapshot

    def delete(self, key: str) -> None:
        self._conn.execute(
            f"DELETE FROM {self._TABLE} WHERE key=?",
            (key,),
        )

    def integrity_report(self) -> dict[str, object]:
        return sqlite_integrity_report(
            self._conn,
            expected_application_id=APP_ID_OPERATIONAL_STATE,
        )

    def close(self) -> None:
        self._conn.close()

    def __enter__(self) -> "SQLiteOperationalStateStore":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def _rollback_quietly(self) -> None:
        try:
            self._conn.execute("ROLLBACK")
        except sqlite3.Error:
            pass


class SQLiteExperienceMemoryStore:
    """Physically separate append-only learned/trade experience memory."""

    _TABLE = "experience_memory"

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
            ensure_application_id(
                self._conn,
                APP_ID_EXPERIENCE_MEMORY,
            )
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
                    CHECK (lane = 'experience_memory'),
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

            CREATE TRIGGER IF NOT EXISTS
                trg_experience_memory_no_update
            BEFORE UPDATE ON {self._TABLE}
            BEGIN
                SELECT RAISE(ABORT, 'append-only experience: UPDATE forbidden');
            END;

            CREATE TRIGGER IF NOT EXISTS
                trg_experience_memory_no_delete
            BEFORE DELETE ON {self._TABLE}
            BEGIN
                SELECT RAISE(ABORT, 'append-only experience: DELETE forbidden');
            END;
            """
        )

    def append(
        self,
        record: DurableRecord,
        *,
        committed_at_ns: int | None = None,
    ) -> StoredExperienceRecord:
        if record.lane is not PersistenceLane.EXPERIENCE_MEMORY:
            raise WrongExperienceLaneError(
                "Experience Memory accepts only experience_memory records"
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
            existing = self.get(record.record_id)
            if existing is not None:
                raise IdempotencyConflictError(record.record_id) from exc
            raise StoreError(str(exc)) from exc
        except sqlite3.Error as exc:
            self._rollback_quietly()
            raise StoreError(str(exc)) from exc

        return StoredExperienceRecord(
            ordinal=ordinal,
            committed_at_ns=commit_ns,
            record=record,
        )

    def append_idempotent(
        self,
        record: DurableRecord,
        *,
        committed_at_ns: int | None = None,
    ) -> tuple[StoredExperienceRecord, bool]:
        if record.lane is not PersistenceLane.EXPERIENCE_MEMORY:
            raise WrongExperienceLaneError(
                "Experience Memory accepts only experience_memory records"
            )
        existing = self.get(record.record_id)
        if existing is not None:
            if existing.record != record:
                raise IdempotencyConflictError(
                    f"record_id collision/content mismatch: {record.record_id}"
                )
            return existing, False
        try:
            return self.append(
                record,
                committed_at_ns=committed_at_ns,
            ), True
        except IdempotencyConflictError:
            existing = self.get(record.record_id)
            if existing is None or existing.record != record:
                raise
            return existing, False

    def get(self, record_id: str) -> StoredExperienceRecord | None:
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
    ) -> tuple[StoredExperienceRecord, ...]:
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

    def integrity_report(self) -> dict[str, object]:
        return sqlite_integrity_report(
            self._conn,
            expected_application_id=APP_ID_EXPERIENCE_MEMORY,
        )

    def close(self) -> None:
        self._conn.close()

    def __enter__(self) -> "SQLiteExperienceMemoryStore":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def _rollback_quietly(self) -> None:
        try:
            self._conn.execute("ROLLBACK")
        except sqlite3.Error:
            pass

    @staticmethod
    def _from_row(row: sqlite3.Row) -> StoredExperienceRecord:
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
        return StoredExperienceRecord(
            ordinal=int(row["ordinal"]),
            committed_at_ns=int(row["committed_at_ns"]),
            record=record,
        )


__all__ = (
    "OperationalSnapshot",
    "SQLiteExperienceMemoryStore",
    "SQLiteOperationalStateStore",
    "StoredExperienceRecord",
    "StoreError",
    "WrongExperienceLaneError",
)
