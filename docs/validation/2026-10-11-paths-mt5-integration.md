# KATARINA AI — workspace paths and integration verification (2026-10-11)

## Scope and source
- Public repository `alfaauliau-katarinaAI/Katarina-AI`, branch `main`.
- Path correction originally committed in [`0b0658e3`](https://github.com/alfaauliau-katarinaAI/Katarina-AI/commit/0b0658e3585e41cef0109484a83229d8c6f878bc).
- The 17 research Python entrypoints, the read-only observer CMD launcher, and the analog scheduled-task *registration script* no longer depend on the old hard-coded checkout locations. They resolve relative to their script/repository locations.
- No observer schedule was enabled in this verification. No broker order was sent; no EA was attached to a live chart.

## Verified checks
| Check | Evidence on Windows VPS |
| --- | --- |
| Python sources | Python syntax/compileall passed |
| Python unit regression | 639 tests passed |
| Python integration regression | 22 tests passed |
| Python static regression | 96 tests passed, including 4 workspace-path regression tests |
| Repository hygiene | `PASS_REPOSITORY_HYGIENE` |
| Stage 10 local data recovery | `PASS_STAGE10_LOCAL_FINAL_CLEARANCE` |
| Stage 11–40 body framework | `PASS_KATARINA_BODY_FRAMEWORK_11_40` |
| Stage 11–40 functional body | `PASS_KATARINA_BODY_LOCAL_10_40` after Stage 10 evidence creation |
| Cross-stage fail-closed | `PASS_KATARINA_CROSS_STAGE_FAIL_CLOSED` |
| MetaEditor native compile | 18 EA/test MQ5 targets passed, 0 errors, 0 warnings |
| Python→MetaTrader5 API | initialize returned true; 74 symbols reported; expected sample symbols present |
| Read-only market observer | 7 of 7 symbols inspected, 0 failures, 0 orders; process exit 0 |
| VPS main pull | `git pull --ff-only` completed with clean worktree |
| Static website script parsing | Node `--check` passed on 5 JS files |

Native build evidence was written privately on the VPS at `C:\KatarinaDev\artifacts\mql5-20261011-check\5606063248194c029647795371f2cf7e\build-evidence.json`. It reports `PASS_MQL5_BUILD`, `runtime_verified=false`, and `live_execution_enabled=false`. The development branch's backend results were checked before the website-only main updates; the workspace-path tests were rerun against updated canonical `main`.

## Intentional release limitations
- **Live trading remains disabled.** Compilation is not proof of order-routing success, profitability, broker portability, or unattended stability.
- Body stages with **policy pending**: 14, 15, 16, 17, 38. This is an expected truthful state, not cleared by this audit.
- Body stages with **Windows runtime validation pending**: 35, 36, 38. MetaEditor compilation confirms MQL build correctness only; it does not substitute for isolated Strategy Tester execution or live-readiness authorization.
- Trading data observed on a weekend may be stale; the observer's failure-safe WAIT gate is appropriate and is not evidence of a profitable setup.
- Do not enable legacy scheduled tasks automatically, expose credentials, or modify risk limits as a side effect of path repair.
- The prior dirty checkout at `C:\KatarinaDev\github-main` was intentionally left untouched to preserve its local work. The maintained working repositories are `C:\KatarinaGitBridge` and `C:\KatarinaDev\mt5-test-workspace`.

**Conclusion:** Path portability, source linkage, static checks, MQL compilation and read-only MT5 communication passed. Production/live authorization and full broker/tester validation are separate future gates.
