# Katarina Stage 06 — Windows Compatibility Baseline

**Status:** ACTIVE VALIDATION BASELINE  
**Stage:** 06  
**Architecture:** x64

## Decision

Windows Server 2012 R2 is deliberately **deferred**.

It is not a blocker for Stage 06 freeze and is not part of the current modern-Windows validation matrix.

The project will first prove the bridge on newer Windows hosts. Windows Server 2012 R2 compatibility can be revisited later only if the finished system still needs to deploy there.

## Preferred validation hosts

1. Windows Server 2022 x64
2. Windows 11 x64

These are the preferred environments for current compile/runtime proof.

## Additional compatibility-validation hosts

- Windows Server 2019 x64
- Windows Server 2016 x64
- Windows 10 x64

These remain useful compatibility targets, but they are not the preferred long-term production baseline.

## Deferred host

~~~text
Windows Server 2012 R2 x64
→ DEFERRED
→ does not block Stage 06
→ revisit after the modern-Windows implementation is complete
~~~

## Explicitly out of scope

- 32-bit Windows
- any environment that cannot run the current 64-bit MetaEditor/MT5 toolchain
- legacy compatibility hacks that weaken the modern Windows implementation

## Stage 06 freeze rule

Stage 06 may freeze after modern-Windows proof succeeds.

Minimum host proof:

~~~text
Windows Server 2022 x64
OR
Windows 11 x64
        ↓
MetaEditor compile
        ↓
0 errors
0 warnings
        ↓
EX5 artifacts exist
        ↓
MQL self-test PASS
        ↓
Standard account probe PASS
        ↓
Cent account probe PASS
        ↓
Final Stage 06 audit
~~~

Windows Server 2012 R2 is not required for this gate.

## Host preflight

Use:

~~~powershell
powershell -ExecutionPolicy Bypass -File .\scripts\mt5\check_stage06_host.ps1
~~~

Expected classifications:

~~~text
Windows 11 x64          → PREFERRED
Windows Server 2022     → PREFERRED
Windows Server 2019     → COMPATIBILITY
Windows Server 2016     → COMPATIBILITY
Windows 10 x64          → COMPATIBILITY
Windows Server 2012 R2  → DEFERRED
32-bit Windows          → UNSUPPORTED
~~~

## Compile proof

Use:

~~~powershell
powershell -ExecutionPolicy Bypass -File .\scripts\mt5\compile_stage06.ps1 `
  -TerminalDataPath "<MT5 DATA FOLDER>" `
  -MetaEditorPath "<METAEDITOR64.EXE>"
~~~

The compile proof now:

- rejects deferred/unsupported hosts for the current freeze proof;
- reads MetaEditor logs explicitly as UTF-16LE;
- requires exactly zero compile errors;
- requires exactly zero warnings;
- requires each EX5 artifact to exist and be non-empty;
- records SHA-256 hashes for source and compiled artifacts;
- writes machine-readable compile evidence to:
  `build/mt5/stage06_compile_evidence.json`.

## Stage 33 alignment

When full CI is built later, the preferred Windows CI baseline is Windows Server 2022 x64.

A self-hosted runner can later provide MetaEditor/MT5-specific compile/runtime capability without changing the Stage-06 bridge design.

## Compatibility policy

Compatibility must not be obtained by weakening these invariants:

- fail-closed execution;
- mandatory native SL;
- one bridge identity/reconciliation authority;
- complete snapshot semantics;
- no discretionary strategy in MQL5;
- no blocking transport work in fast MT5 event handlers.

If a legacy host later requires changes that violate these rules, that host is rejected rather than weakening Katarina.


## One-command verification

On a supported modern Windows host, the full automated host-side proof can be started with:

~~~powershell
powershell -ExecutionPolicy Bypass -File .\scripts\mt5\verify_stage06_modern_windows.ps1 `
  -TerminalDataPath "<MT5 DATA FOLDER>" `
  -MetaEditorPath "<METAEDITOR64.EXE>"
~~~

This chains:

1. modern-Windows host classification;
2. Stage-06 Python static bridge tests;
3. Windows compatibility regression tests;
4. strict MetaEditor compile proof;
5. EX5 artifact/hash evidence generation.

It intentionally stops before MT5 runtime proof, which still requires running the MQL self-test and standard/cent account probes inside MT5.
