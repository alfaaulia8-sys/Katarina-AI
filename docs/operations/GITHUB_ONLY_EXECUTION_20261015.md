# KATARINA AI — GitHub-only execution gates (2026-10-15)

## Scope
All current development and verification should be performed in GitHub or reproducible Linux CI. VPS, native MetaEditor, broker terminal, MT5 runtime, and live orders are explicitly deferred. Do not alter strategy or risk policy defaults without separate authorization. Keep live execution disabled.

## Verified source baseline
- Canonical public repository: `alfaauliau-katarinaAI/Katarina-AI`, default branch `main`.
- `src/katarina/policies/strategy.py` defaults to `UNFINALIZED` and `live_execution_authority=False`.
- `src/katarina/policies/risk.py` defaults to `UNFINALIZED`, `live_risk_ready=False`, and `live_execution_authority=False`.
- `scripts/governance/audit_dependency_links.py` performs static Python syntax/import, MQL include, JSON and website link checks. A passing result is not evidence of native compilation or MT5 runtime.
- The historical baseline in `GITHUB_FIRST_STATUS_20261011.md` reports earlier Windows tests; those results are not revalidated by this note.

## Required GitHub acceptance sequence
1. Inventory `.github/workflows` and map every job/trigger/runner to its source commands. Record failing job IDs and failure logs before editing workflows.
2. Run deterministic Python unit tests and integration tests, with test counts, command, commit SHA and artifact logs.
3. Run `python scripts/governance/audit_dependency_links.py` on a clean checkout and archive `build/validation/dependency-links.json`.
4. Confirm secrets are neither committed nor emitted by CI, and workflows use least-privilege tokens and pinned/controlled dependencies.
5. Add regression coverage for any confirmed defect before changing affected code. Re-run the affected tests and the full suite.
6. Require a green run for the exact final commit SHA before calling GitHub-only work complete.

## Explicit exclusions from GitHub-only PASS
- Native MQL5/MetaEditor compilation, broker execution, tick-accurate backtest and forward test.
- Synchronization with or cleanup of VPS workspaces.
- Profitability, strategy validation, policy finalization and live authorization.

## Current status
- GitHub source audit: inspected key static audit and policy modules; full CI jobs and logs not yet inspected.
- Acceptance sequence: **NOT COMPLETE**. No current CI PASS, unit test count or integration result is claimed here.
- VPS connectivity: deferred by project owner.

## Completion rule
Mark GitHub-only acceptance **PASS** only when the exact final commit has reproducible CI artifacts for tests, static audits and security checks. Keep non-GitHub runtime gates separately **PENDING**.
