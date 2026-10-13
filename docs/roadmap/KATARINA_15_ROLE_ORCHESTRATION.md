# KATARINA V1 — Fifteen-Role Orchestrated Team (GitHub Runner)

Status: IMPLEMENTED RESEARCH ENGINEERING COORDINATION; not 15 independent paid LLM agents, not autonomous code writing.

## Team architecture

- Scheduler: locks the exact 13–19 October 2026 seven-day plan, identifies today's WIB priority, creates an SHA-256 plan receipt, limits concurrency to four and retry policy to one.
- Eleven parallel specialist tasks: **Ideas, Coding, Mathematics, Logic, Builder, Debugger, Runner Operations, Data Engineering, AI Integration, Infrastructure/RAM, Security/Risk**.
- QA: runs all repository unit/static/integration tests, then verifies **all eleven** specialist artifacts were produced for the *same commit and scheduler receipt*. Tampered/missing/stale material is BLOCKED.
- Manager: validates QA and specialist handoffs, sets next locked priority, explicitly lists unfinished external AI and market data blockers.
- Release: records engineering readiness versus actual release decision. V1 stays BLOCKED without independent market evidence.
- Total fifteen roles: scheduler + eleven specialists + QA + manager + release.

## Exact workflow

`.github/workflows/katarina-orchestrated-team.yml` — **workflow_dispatch only**, read-only GitHub token, GitHub-hosted Ubuntu, no self-hosted/VPS runner.

`scheduler → 11 role jobs (max 4 concurrent) → QA → manager → release`

Each stage uploads SHA-256 integrity-receipted JSON artifacts scoped to `GITHUB_SHA`, with seven-day retention. These receipts are **checksums, not cryptographic signatures**.

The scheduler is an **execution DAG controller**, not an always-on background task. The workflows only work after a GitHub Actions run is started by the user or a separate authorized trigger. The orchestration itself is reproducible.

## What each team can actually do

| Team | Implemented gate | Not implied |
|---|---|---|
| Ideas | Generates synthetic rule genomes using Strategy Discovery | Real-market alpha |
| Coding | Parses/compiles and fingerprints core modules | Autonomous code commits |
| Math | Confirms conservative, fee/spread stressed quote model | Broker-calibrated slippage |
| Logic | Checks causal features, frozen holdout, WAIT | Live execution authority |
| Builder | Compiles and checks integration dependencies | Running EA on VPS |
| Debugger | Performs syntax health audit and records failed-test rule | Self-healing code rewrites |
| Runner Ops | Verifies scoped manual workflow, concurrency and permissions | Persistent background runner |
| Data | Validates synthetic OHLC ordering/geometry | Real broker dataset certified |
| AI Integration | Checks multiple model authors and safe request shape | Actual API responses confirmed |
| Infrastructure | Reads available runner memory without process killing | RAM cleanup on VPS |
| Security/Risk | Checks GitHub token read-only and no unattended deployments | Security penetration audit |
| QA | Full regression + receipts and fail-closed checks | Proof of profitability |
| Manager | Enforces delivery priority and verified QA gates | Unlimited LLM delegation |
| Release | Prevents live release until prerequisites are met | Trading release |

## Error handling and RAM

An error **fails the corresponding specialist or QA job**, and Manager/Release cannot invent a PASS. The Debugger performs bounded diagnostics; no automatic rewrite/retry loops or merge permissions are granted in this version. A future code-improvement bot must use a sandbox and PR review gate.

GitHub-hosted runners are ephemeral; there is no persistent RAM leak to clean between jobs. The Infrastructure worker checks its own available RAM and kills **zero** processes; VPS cleaning is explicitly out of scope.

## End-to-end demonstration

A one-shot smoke gate in `.github/workflows/katarina-body-ci.yml` runs only when a commit includes `[team-v2-smoke]`. It verifies actual matrix parallelism plus QA → manager → release receipts. Otherwise Body CI executes normally. The primary manual team workflow remains the reusable run entrypoint.

## Project deadline

The Manager uses the locked roadmap `docs/roadmap/KATARINA_7_DAY_BUILD_2026-10-13_TO_19.md`; its current priority follows the **Asia/Jakarta date** and the deadline is October 19. Research engineering can PASS while V1 release remains explicitly BLOCKED if real AI or independent market evidence is absent.
