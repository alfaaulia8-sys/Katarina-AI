from __future__ import annotations

import sqlite3
from pathlib import Path
from typing import Callable


SCHEMA_VERSION_V1 = 1

APP_ID_EVENT_JOURNAL = 0x4B4A4E31
APP_ID_OPERATIONAL_STATE = 0x4B4F5031
APP_ID_EXPERIENCE_MEMORY = 0x4B455831


class SQLiteStoreError(RuntimeError):
    pass


class SchemaVersionError(SQLiteStoreError):
    pass


class ApplicationIdError(SQLiteStoreError):
    pass


def configure_connection(
    conn: sqlite3.Connection,
    path: Path,
    *,
    busy_timeout_ms: int,
) -> None:
    mode = str(conn.execute("PRAGMA journal_mode=WAL").fetchone()[0]).lower()
    if mode != "wal" and path != Path(":memory:"):
        raise SQLiteStoreError(f"failed to enable SQLite WAL mode: {mode}")

    conn.execute("PRAGMA synchronous=FULL")
    synchronous = int(conn.execute("PRAGMA synchronous").fetchone()[0])
    if synchronous != 2:
        raise SQLiteStoreError(
            f"SQLite synchronous mode is not FULL: {synchronous}"
        )

    conn.execute("PRAGMA foreign_keys=ON")
    conn.execute(f"PRAGMA busy_timeout={int(busy_timeout_ms)}")


def ensure_application_id(conn: sqlite3.Connection, expected: int) -> None:
    current = int(conn.execute("PRAGMA application_id").fetchone()[0])
    if current == 0:
        conn.execute(f"PRAGMA application_id={expected}")
        current = int(conn.execute("PRAGMA application_id").fetchone()[0])
    if current != expected:
        raise ApplicationIdError(
            f"SQLite application_id mismatch: expected {expected}, got {current}"
        )


def migrate_v1(
    conn: sqlite3.Connection,
    *,
    create_schema: Callable[[], None],
) -> None:
    version = int(conn.execute("PRAGMA user_version").fetchone()[0])
    if version == 0:
        create_schema()
        conn.execute(f"PRAGMA user_version={SCHEMA_VERSION_V1}")
        version = int(conn.execute("PRAGMA user_version").fetchone()[0])
    if version != SCHEMA_VERSION_V1:
        raise SchemaVersionError(
            f"unsupported SQLite schema version: {version}"
        )


def integrity_report(
    conn: sqlite3.Connection,
    *,
    expected_application_id: int,
) -> dict[str, object]:
    quick = tuple(
        str(row[0])
        for row in conn.execute("PRAGMA quick_check").fetchall()
    )
    foreign = tuple(
        tuple(row)
        for row in conn.execute("PRAGMA foreign_key_check").fetchall()
    )
    app_id = int(conn.execute("PRAGMA application_id").fetchone()[0])
    version = int(conn.execute("PRAGMA user_version").fetchone()[0])
    mode = str(conn.execute("PRAGMA journal_mode").fetchone()[0]).lower()
    sync = int(conn.execute("PRAGMA synchronous").fetchone()[0])

    passed = (
        quick == ("ok",)
        and not foreign
        and app_id == expected_application_id
        and version == SCHEMA_VERSION_V1
        and sync == 2
        and mode in {"wal", "memory"}
    )
    return {
        "quick_check": quick,
        "foreign_key_violations": foreign,
        "application_id": app_id,
        "expected_application_id": expected_application_id,
        "schema_version": version,
        "journal_mode": mode,
        "synchronous": sync,
        "passed": passed,
    }


__all__ = (
    "APP_ID_EVENT_JOURNAL",
    "APP_ID_EXPERIENCE_MEMORY",
    "APP_ID_OPERATIONAL_STATE",
    "ApplicationIdError",
    "SCHEMA_VERSION_V1",
    "SQLiteStoreError",
    "SchemaVersionError",
    "configure_connection",
    "ensure_application_id",
    "integrity_report",
    "migrate_v1",
)
