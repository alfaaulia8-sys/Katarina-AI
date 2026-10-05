# Stage 10 Steps 03-05 — GitHub Reference Notes

Status: REVIEWED BEFORE LOCAL IMPLEMENTATION

## Step 03 — Separate operational state from experience memory

Reference:
- Novi memory event model / event sourcing:
  https://github.com/GiannisGlp/Novi/blob/8b702d91ff93040b6759a673d89f6c31d58cff69/docs/04-memory-and-knowledge/archive/30_MEMORY_EVENT_MODEL_AND_EVENT_SOURCING.md
- Existing Stage-10 event-store reference:
  pyeventsourcing/eventsourcing persistence design.

Useful prior-art idea:
- immutable event history, retained memory, and current state/projection are
  different concepts;
- high-volume transient observations do not all belong in permanent memory;
- state is a projection, not the immutable event truth.

KATARINA adaptation:
- three physically distinct SQLite files:
  event_journal.sqlite3, operational_state.sqlite3, experience_memory.sqlite3;
- Event Journal is recovery-authoritative;
- operational snapshots are replaceable/rebuildable only;
- Experience Memory is append-only and advisory;
- none of the three stores grants live execution authority.

## Step 04 — Idempotent writes and restart recovery

Reference:
- mcp-memory-server SQLite store:
  https://github.com/dustinspace217/mcp-memory-server/blob/358133548d9640a222fdac5dc029219d15c6ddca/sqlite-store.ts
- pyeventsourcing recorder/unique-sequence design from Step 02.

KATARINA adaptation:
- deterministic record IDs remain the idempotency key;
- replay of an identical deterministic record returns the existing row;
- the same ID with different content fails closed;
- idempotency survives process restart because it is enforced by the database;
- operational snapshots are only restart acceleration hints;
- invalid/ahead/corrupt snapshot state causes full Event Journal replay;
- restart recovery never sets RISK or EXECUTION_ARMED readiness.

## Step 05 — Schema migrations and integrity checks

References:
- XiaDown SQLite migrations:
  https://github.com/arnoldhao/xiadown/blob/c8e33101987f123dd8d8504a3ec15bd296d69e13/internal/infrastructure/persistence/sqlite_migrations.go
- OpenClaw integrity and recovery:
  https://github.com/openclaw/openclaw/blob/4455f15b09e2786d0f8d3ff89848c7d54b237028/docs/reference/database-schemas/integrity-and-recovery.md

Useful prior-art ideas:
- database application identity must be verified before migrations;
- schema version must be explicit and future/unknown versions refused;
- integrity and foreign-key checks are admission gates, not optional logging;
- migrations are append-forward governance, not silent schema rewriting.

KATARINA adaptation:
- distinct SQLite application_id for each Stage-10 store;
- PRAGMA user_version governs V1 schema;
- future/unknown schema versions fail closed;
- quick_check + foreign_key_check + application_id + schema version +
  WAL/synchronous state are verified;
- synchronous=FULL is retained for Stage-10 safety-sensitive persistence.

## Rule

These projects are prior-art references only. KATARINA code is independently
implemented against the frozen Stage 01-09 invariants and never inherits an
external project's trading authority or risk policy.
