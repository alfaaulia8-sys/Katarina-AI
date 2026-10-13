# Katarina Management — Readiness Workstream (14 October 2026)

## Authority and boundaries
Owner authorized **GAS EKSEKUSI for Katarina Management first**. Do not implement the trading brain/Neuro-Link or change MT5, broker accounts, active trading deployment, or Owner manual positions in this workstream. The Owner's finalized Master Design remains authoritative. This branch is isolated and has not been merged to main.

## What was already present
- `scripts/ai/katarina_flow_v2.py`: Scheduler, 11 specialists, QA, Manager, Release (15-role workflow).
- `.github/workflows/katarina-orchestrated-team.yml`: manual-only, GitHub-hosted, max 4 concurrent specialists, no automatic merges/deployment.
- `scripts/ai/katarina_team.py`: four deterministic engineering workers.
- Both pipelines were *research/engineering test harnesses*, not independently capable LLM coding agents.

## Implemented on this branch
1. Versioned task manifest: `config/management-workplan-v1.json` — one bounded source-audit assignment per specialist.
2. `scripts/ai/management_workplan.py` — validates role ownership, safe repository paths, max bytes, syntax/JSON shape, source digest, line count and audit flags. QA replays task evidence against actual pinned source; Manager independently checks full specialist coverage. Path traversal, stale/tampered receipts and source drift fail closed. No arbitrary command execution.
3. Extended `katarina_flow_v2.py` to bind Scheduler -> Specialists -> QA -> Manager to the same pinned manifest and file-level evidence, while preserving the existing real-money trading and release blocks.
4. Fixed Windows WIB timezone dependency: uses UTC+07:00 directly instead of requiring third-party `tzdata`; valid for current Jakarta management dates.
5. `scripts/ai/management_resources.py` — RAM-aware local concurrency recommendation (1/2/4 workers), disk safety check, read-only cache inventory. Protects memory/data/backup/broker-related directories. **No files deleted and no services killed.**
6. Added fail-closed regression tests for task ownership, path safety, evidence replay, tampering, duplicate assignment, future cache safety, and low-memory limits.

## Observed tests and machine evidence
- At 14 October 2026 on the connected Windows VPS isolated Git worktree, 25 focused management and workflow-safety tests passed:
  `py -3 -m unittest tests.static.test_github_action_fanout tests.unit.governance.test_management_workplan tests.unit.governance.test_management_resources tests.unit.governance.test_katarina_flow_v2 -q`
- Extended governance suite: **46 tests passed** using `py -3 -m unittest discover -s tests/unit/governance -p test_*.py -q`. No full repository test suite has been claimed.
- Snapshot available RAM approximately 263 MiB out of 2047 MiB; drive C: approximately 8.96 GiB free.
- Recommended **one local Management worker at a time** in that low-memory state. This is an advisory gate, not automatic control of unrelated applications.
- After testing, **12 developer-only Python cache directories** were safely removed from the isolated QA worktree; remaining cache candidates there: 0. No production or primary-source cache was deleted.
- The primary Windows `github-main` worktree had pre-existing uncommitted changes. Those changes were not overwritten. All QA work used a new dedicated detached worktree, `C:\KatarinaDev\management-qa-20261014`.

## Remaining blockers: do not misrepresent readiness
- **Not autonomous coding agents yet:** specialists currently perform deterministic engineering audits and bounded synthetic research; no independently verified agentic coding or patch proposal-and-approval loop.
- The end-to-end GitHub-hosted **full unit/static/integration** regression and production-independent releases have not been verified on this branch. The 25 targeted tests do not substitute for full CI.
- No external LLM workers were activated and no cloud/API spend was authorized.
- Real VPS runtime, MT5 processes, broker-dependent tasks and live trading were not changed or interrupted.
- No cache in production was purged without evidence of dependency safety.
- Workflow `release` remains fail-closed; no automatic deployment or trading.

## Next Management-only gate
1. Introduce tightly scoped **patch proposal -> QA -> Manager approval -> merge/release** handoff with no arbitrary local shell execution by untrusted roles.
2. Verify external model connectivity only after Owner grants provider/budget approval; enforce source provenance, cost limits and output checks.
3. Run the full non-trading GitHub validation suite and acceptance of all 15 roles with reproducible receipts; block on missing evidence.
4. Make Manager genuinely able to track task status/blockers and inspect resources before scheduling, then verify safe release and rollback.
5. Keep trading Katarina AI work **on hold until Management has passed these gates**.

## Rollback
The management implementation is on a separate branch. To abandon its changes, do not merge it. The main branch, trading terminals, and unrelated worktrees remain unchanged.


## Additional Management QA hardening — 14 October 2026

Work continues on isolated branch `feature/management-hardened-qa-20261014`; no MT5, trading code, broker positions, main worktree or production process has been modified.

- **Independent specialist replay:** QA now recalculates each deterministic specialist result instead of trusting a re-hashed claim. The infrastructure worker's host-specific memory numbers are excluded from byte-exact replay, but its immutable safety claims are independently verified.
- **Exact QA handoff:** Manager validates all QA fields against its own reproduction, not just selected summary fields.
- **Release authorization:** Release independently replays Manager/QA and detects re-sealed forged Management results. It still never promotes trading.
- **Serial local acceptance:** `scripts/ai/management_acceptance.py --commit <clean-HEAD-SHA>` performs one-at-a-time Scheduler -> 11 specialists -> QA -> Manager -> Release checks. CLI refuses a dirty/unpinned checkout and stops if memory/disk are critically low. It returns explicit blockers without claiming external AI agents.
- **Review-only change proposals:** `scripts/ai/management_change_control.py --proposal <review-json>` validates a SHA-pinned change limited to Management tooling/tests, checks Python syntax and emits a bounded diff. It does **not** apply the patch, run it, approve it, merge, deploy, or send orders. Owner plus independent QA approval remain required for any future source mutation.
- **Adversarial regression:** tests cover forged specialist claims with recomputed checksum, forged QA, forged Manager summary, stale proposals, trading-scope denial, invalid syntax, unchanged source, and non-mutation guarantees.
- **Local tests verified on this hardening branch:** 55 governance unit tests and 3 static workflow fanout tests passed, sequentially on the isolated VPS worktree. This is NOT a substitute for cloud full unit/static/integration regression.
- **Still incomplete:** real autonomous coding workers, externally authenticated models, cloud end-to-end regression on this branch, and actual human-approved patch apply/release workflow. No claim of 100% Management autonomy or trading-ready release is made.
