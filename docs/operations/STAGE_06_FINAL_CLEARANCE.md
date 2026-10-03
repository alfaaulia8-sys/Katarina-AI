# Stage 06 — Final Clearance Procedure

**Status:** FINALIZED / FROZEN v1.0.0  
**Bridge design:** v0.5.0  
**Clearance automation:** v1.0.0

## Objective

Stage 06 is frozen after the exact source tree, modern-host compiler result, MQL self-test and static regressions are bound into one auditable proof under ADR-0010.

## One-command entry point

Run on supported modern Windows x64 with MT5, MetaEditor and Python:

~~~powershell
powershell -ExecutionPolicy Bypass -File .\scripts\mt5\complete_stage06.ps1 `
  -TerminalDataPath "<MT5 DATA FOLDER>" `
  -TerminalCommonDataPath "<MT5 COMMON DATA FOLDER>" `
  -MetaEditorPath "<METAEDITOR64.EXE>"
~~~

Freeze proof completed on Windows Server 2022 x64. Windows Server 2012 R2 remains deferred.

## Automated chain

The runner:

1. removes stale Stage-06 runtime evidence;
2. validates the Windows host;
3. runs Stage-06 Python/static regressions;
4. compiles the bridge, self-test and account probe in MetaEditor;
5. requires zero errors and zero warnings;
6. requires fresh non-empty EX5 artifacts;
7. records SHA-256 hashes and the complete MQL source/include manifest;
8. runs the MQL self-test on the freeze-qualified modern host;
9. re-runs the static regression suite;
10. verifies current source still matches the compiled source manifest;
11. creates final clearance evidence.

## Read-only account probe boundary

Real STANDARD_LIKE and CENT_LIKE broker probes remain available as read-only diagnostics, but under ADR-0010 they are deferred to Stage 36/38 and are not Stage-06 freeze blockers. Stage 06 makes no broker-by-broker production compatibility claim.

## Final artifacts

~~~text
build/mt5/stage06_compile_evidence.json
build/mt5/stage06_final_clearance.json
build/mt5/STAGE_06_FINAL_AUDIT_CANDIDATE.md
~~~

Final machine result:

~~~text
PASS_STAGE06_FINAL_CLEARANCE
~~~

## Anti-stale protections

The final audit fails if compile warnings/errors exist, EX5 is missing, design versions differ, the MQL self-test fails, any MQL/include source changed after compilation, or static regressions fail.

## Privacy

Evidence must not contain passwords, investor passwords, VPS credentials or API keys. The account probe stores only the last four login digits for local evidence correlation.

## Freeze rule

`stage06_final_clearance.json` reported `PASS_STAGE06_FINAL_CLEARANCE` on the governed Windows Server 2022 proof run, so Stage 06 is now `FROZEN v1.0.0`.

Freeze provenance is recorded in `docs/reviews/STAGE_06_FREEZE_RECORD.md`.
