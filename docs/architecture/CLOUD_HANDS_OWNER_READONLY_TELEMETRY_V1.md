# Cloud Hands and Owner telemetry — offline fan-in contract

This module **does not operate a cloud service** and has no sender, socket,
broker connection, credential management, or action-capable Owner command.

`offline_hand_telemetry.consolidate_hand_reports` accepts only immutable
research receipts produced by the existing adaptive Entry/Exit handoff.

It validates local SHA256 data integrity, evidence timestamps, distinct
hand/symbol pairs, and research-only flags; a future-dated or mutated receipt
is rejected. Opposing BUY/SELL research views on the same symbol are surfaced
as a conflict, never resolved into a trade. Output remains sorted,
deterministic, read-only and explicitly unauthenticated.

**A hash is NOT proof of hand identity.** The hand ID can be user-supplied,
therefore output declares `cloud_authenticated=False`; authentication,
transport replay prevention, expiry/SLO semantics, privacy, owner authorization,
and safe offline deployment remain open in Master Design D6.

No synthetic sample or test authorizes trade execution or a strategy promotion.

Run on GitHub Actions runner:
`PYTHONPATH=src python -m unittest discover -s tests/unit/intelligence -p test_offline_hand_telemetry.py -v`.

## Cross-Hand causal evidence honesty (offline)

- Separate Hands that report the same `(symbol, source_sha256)` are
  flagged as `REUSED_CAUSAL_SOURCE_NOT_INDEPENDENT`. Multiple copies of
  the same closed-bar source cannot increase effective research sample size.
- An opposing BUY/SELL candidate for one symbol is flagged as
  `CONFLICTING_RESEARCH_SIDES` without suggesting which direction to trade.
- Every positive candidate retains `UNAUTHENTICATED_HAND_ORIGIN` even when
  no conflict or repeated SHA is found. Different SHA values do not prove
  independent samples or authentic identities.
- Malformed research states (forged `LIVE_READY` action, invalid entry
  geometry, contradictory WAIT/candidate fields, or invalid hand IDs) are
  rejected even if the sender recomputes the local SHA-256 receipt.
- The additional `research_integrity_flags` and
  `shared_source_symbols` are read-only disclosure for Owner review;
  **they cannot authorize trades**, source promotion, or external commands.
- No new time-to-live policy, consensus/weighting rules, authentication
  thresholds, or cloud commands are invented. These remain Owner D5/D6.
