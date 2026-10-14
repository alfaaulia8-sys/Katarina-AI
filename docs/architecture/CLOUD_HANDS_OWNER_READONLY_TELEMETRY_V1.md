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
