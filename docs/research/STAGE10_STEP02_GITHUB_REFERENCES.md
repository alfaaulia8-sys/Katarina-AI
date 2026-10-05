# Stage 10 Step 02 — GitHub Reference Notes

Purpose: record the GitHub implementation patterns reviewed before local
implementation of append-only durable records and deterministic IDs.

These references are design inputs only. KATARINA AI does not copy their code
or inherit their execution authority model.

## 1. pyeventsourcing/eventsourcing

Pinned reference:
- commit: `575d42c10a821828639b90178ed56703abe9c9f1`
- file: `eventsourcing/sqlite.py`
- docs: `docs/topics/persistence.rst`

Relevant patterns reviewed:

- explicit SQLite transactions with BEGIN / COMMIT / ROLLBACK;
- WAL for file-backed SQLite;
- unique event positions enforced by primary keys;
- insertion-only recorder semantics;
- sequential and unique event storage;
- atomic recording to prevent partial durable state;
- anti-overwrite as a core event-sourcing invariant.

KATARINA adaptation:

- one global append-only Event Journal with monotonic ordinal;
- deterministic SHA-256 record ID is additionally required;
- UPDATE and DELETE are blocked by SQLite triggers;
- Stage-10 persistence cannot arm execution or approve risk.

## 2. SawyerHood/omegacode

Pinned reference:
- commit: `748d686a7950b3466e8d7fd014db32c4fb9fccf5`
- file: `DESIGN.md`

Relevant pattern reviewed:

- deterministic SHA-256 key construction from canonical semantic material.

KATARINA adaptation:

- domain-separated SHA-256;
- canonical UTF-8 JSON;
- sorted object keys and no insignificant whitespace;
- byte values have an explicit tagged hexadecimal representation;
- floating-point values are rejected from durable identity material;
- fixed-point integer units remain authoritative.

## 3. SuperScalar

Pinned reference:
- commit: `5dc68381cf5258b6d6028975cc356b79cfc30e54`
- file: `CHANGELOG.md`

Relevant durability pattern reviewed:

- validate that SQLite durability PRAGMAs actually took effect;
- WAL plus `synchronous=FULL` for safety-sensitive persisted state.

KATARINA adaptation:

- startup fails if file-backed SQLite does not enter WAL;
- startup fails if synchronous mode is not FULL;
- busy timeout is explicit.

## Decisions for KATARINA Stage 10 Step 02

1. SQLite is the V1 local persistence backend.
2. Authoritative operational facts use an append-only Event Journal.
3. Every durable record has a deterministic SHA-256 ID.
4. IDs are computed only from semantic event identity, never ingest wall-clock.
5. Database ordinal is monotonic but is not part of deterministic record ID.
6. Duplicate IDs are rejected in Step 02; idempotent replay semantics belong to
   Step 04.
7. Experience Memory records may share the DurableRecord format, but the Event
   Journal refuses them. A physically/logically separate store is Step 03.
8. Raw market ticks/bars and transport telemetry remain transient unless a later
   component emits explicit durable evidence.
9. No persistence record or database state can grant live execution authority.

## Step 02 acceptance target

- deterministic canonicalization tests;
- deterministic ID stability tests;
- payload/sequence mutation changes ID;
- append/read roundtrip;
- monotonic journal ordinal;
- duplicate rejection without overwrite;
- raw UPDATE and DELETE blocked at database level;
- WAL + synchronous FULL verified;
- Event Journal rejects Experience Memory lane;
- full unit regression remains green.
