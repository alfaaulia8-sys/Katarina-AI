# Owner cognitive rollback fencing for adaptive Entry/Exit — offline only

When a user explicitly rolls back a research learning checkpoint, the
adaptive/curiosity Entry/Exit review MUST NOT silently read newer virtual
quotes and treat them as a fresh favorable research candidate.

The public read-only `verify_cognitive_history()` now surfaces:
- Active checkpoint SHA and exact active observation SHA
- Chain head SHA, last event kind and timestamp
- All facts verified through the existing append-only receipt chain

`synthesize_offline_research` binds its output receipt to the persisted
chain and active checkpoint. Even if a virtual quote report appears
favorable, it returns WAIT whenever:
1. The latest cognitive history event is an explicit Owner rollback
2. Current virtual quotes do not match the Owner-active checkpoint snapshot
3. The latest ledger timestamp occurs after the requested as-of research time

An invalid ledger hash rejects the entire synthesis before any apparent
learning evidence can be trusted.

A matched, normal research checkpoint is still limited to
`VIRTUAL_EXPERIMENT_REVIEW_ONLY`, never production execution.
No broker, live order, new Risk Governor authority, Owner parameter
threshold, background loop, or source rewriting is introduced.

Run the focused unit tests at:
`tests/unit/intelligence/test_unified_adaptive_research_cycle.py`,
or use the canonical GitHub Actions Body CI.

Still partial versus Master Design: factual multi-market predictive skill,
independent forward broker evidence, confidence calibration, authorized
strategy promotion and exact Owner numerical policies are not implemented.
