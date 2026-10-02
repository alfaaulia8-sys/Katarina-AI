# Stage 06 — Final Clearance Procedure

**Status:** AUTOMATION COMPLETE / EXTERNAL PROOF PENDING  
**Bridge design:** v0.5.0  
**Clearance automation:** v1.0.0

## Objective

Stage 06 is frozen only after the exact source tree, compiler result, runtime tests and account probes are bound into one auditable proof.

## One-command entry point

Run on supported modern Windows x64 with MT5, MetaEditor and Python:

~~~powershell
powershell -ExecutionPolicy Bypass -File .\scripts\mt5\complete_stage06.ps1 `
  -TerminalDataPath "<MT5 DATA FOLDER>" `
  -TerminalCommonDataPath "<MT5 COMMON DATA FOLDER>" `
  -MetaEditorPath "<METAEDITOR64.EXE>"
~~~

Preferred proof hosts: Windows Server 2022 x64 or Windows 11 x64. Windows Server 2012 R2 remains deferred.

## Automated chain

The runner:

1. removes stale Stage-06 runtime evidence;
2. validates the Windows host;
3. runs Stage-06 Python/static regressions;
4. compiles the bridge, self-test and account probe in MetaEditor;
5. requires zero errors and zero warnings;
6. requires fresh non-empty EX5 artifacts;
7. records SHA-256 hashes and the complete MQL source/include manifest;
8. waits for three fresh MT5 runtime proof files;
9. rejects stale or version-mismatched runtime evidence;
10. binds runtime evidence to the exact compile-evidence hash;
11. re-runs the static regression suite;
12. verifies current source still matches the compiled source manifest;
13. creates final clearance evidence.

## Three read-only runtime actions inside MT5

Run `KatarinaStage06SelfTest` once.

Then run `KatarinaStage06AccountProbe` on a standard-like validation account with:

~~~text
InpAccountClass = STANDARD_LIKE
~~~

Then run the same probe on a cent-like validation account with:

~~~text
InpAccountClass = CENT_LIKE
~~~

Stage 06 has no `OrderSend` or `OrderSendAsync` path.

Expected runtime files under MT5 Common/Files:

~~~text
Katarina_Stage06_self_test_result.txt
Katarina_Stage06_account_probe_STANDARD_LIKE.txt
Katarina_Stage06_account_probe_CENT_LIKE.txt
~~~

## Final artifacts

~~~text
build/mt5/stage06_compile_evidence.json
build/mt5/stage06_runtime_evidence.json
build/mt5/stage06_final_clearance.json
build/mt5/STAGE_06_FINAL_AUDIT_CANDIDATE.md
~~~

Final machine result:

~~~text
PASS_STAGE06_FINAL_CLEARANCE
~~~

## Anti-stale protections

The final audit fails if compile warnings/errors exist, EX5 is missing, runtime proof is stale, design versions differ, runtime proof does not bind to the current compile proof, any MQL/include source changed after compilation, static regressions fail, or either account probe/self-test fails.

## Privacy

Evidence must not contain passwords, investor passwords, VPS credentials or API keys. The account probe stores only the last four login digits for local evidence correlation.

## Freeze rule

Only after `stage06_final_clearance.json` reports `PASS_STAGE06_FINAL_CLEARANCE` and the governed project-owner review accepts the evidence may Stage 06 be finalized as `FROZEN v1.0.0`.

All Stage-06 implementation and verification tooling is now present. What remains is execution of the proof on real modern Windows + MT5/MetaEditor and the two account classes; repository-only tooling cannot truthfully fabricate those results.
