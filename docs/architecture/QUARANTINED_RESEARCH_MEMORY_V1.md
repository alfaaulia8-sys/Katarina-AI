# Quarantined lifelong research memory — offline append-only integration

New research-memory path:
`src/katarina/memory/quarantined_research_memory.py`.

- Accepts **real** Adaptive Brain/Smart Entry/Exit `OwnerResearchReceipt`
  research objects. Revalidates the receipt with the existing Cloud Hands
  offline telemetry validator; an arbitrary dictionary is never executable.
- Persists immutable local source evidence with a SHA-256 payload checksum,
  append-only SQLite triggers, and idempotent replays keyed by hand,
  symbol and observation time.
- **All** external/Hand-origin information remains quarantined.
  Recomputed hashes do not prove which person, broker or device supplied it.
- Cross-hand reports with one causal `(symbol, source_digest)` are reported
  as repeated observations of one *claimed* source, not independent alpha
  samples. Different fingerprints are not assumed independent either.
- Read-only curiosity priorities expose where new independent quote sources
  should be collected, without inventing an experiment threshold, modifying
  strategy selection, changing risk budgets or creating broker orders.
- Snapshot reads respect the requested timezone-aware `as_of_utc`.
  Restart/replay and corrupted-payload rejection are regression tested.
- No background ingestion, network listener, Cloud authentication, strategy
  promotion, external data collection or Owner command path is enabled.

This is deliberately **PARTIAL** towards true Selective Lifelong Memory:
source authentication, multi-tier semantic consolidation, procedural/decision
memory, conflict rehabilitation, privacy/retention policy and actual
broker-performance learning remain separate future tasks (Owner D4–D6).

Run `PYTHONPATH=src python -m unittest discover -s tests/unit/memory -p test_quarantined_research_memory.py -v` or use GitHub Body CI.
