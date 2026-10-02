# STAGE 06 — GITHUB REFERENCE AUDIT

**Stage:** 06/40  
**Status:** RESEARCH COMPLETE / ACTIONS INCORPORATED  
**Reviewed:** 2026-10-03

## Purpose

Re-check the remaining Stage-06 MT5 Bridge work against mature or relevant public GitHub implementations before final compiler/runtime proof.

The objective is not to copy another bridge. It is to identify failure modes and verification techniques that Katarina should either adopt now or explicitly defer to the correct later stage.

## References Reviewed

### FX31337/MQL-Compile-Action

Repository:

- `FX31337/MQL-Compile-Action`

Relevant patterns:

- locate MetaEditor and invoke command-line compile;
- explicit `/inc:` include root;
- fresh compiler log per source;
- read MetaEditor log as UTF-16LE;
- treat compiler warnings as failures unless deliberately ignored;
- optional terminal initialization.

Katarina action:

- already incorporated into `compile_stage06.ps1`;
- Stage 06 now requires zero errors + zero warnings;
- stale EX5 is deleted before compile;
- fresh EX5 existence and SHA-256 are evidence.

### EA31337/EA-Tester

Repository:

- `EA31337/EA-Tester`

Relevant patterns:

- clean stale compiled/test artifacts;
- inspect MetaTrader/MetaEditor versions;
- convert/read UTF-16 logs explicitly;
- keep tester logs and reports as first-class evidence;
- separate compilation, test execution and log inspection.

Katarina action:

- compiler evidence is separated from runtime evidence;
- source and EX5 hashes are preserved;
- runtime evidence is collected separately after MT5 execution.

### rodrigoshaller/MTUnit

Repository:

- `rodrigoshaller/MTUnit`

Relevant pattern:

- MQL logic should have tests that execute in the actual MetaTrader/MQL runtime, not only Python/static source inspection.

Katarina action:

- `KatarinaStage06SelfTest.mq5` remains mandatory;
- self-test now emits a machine-readable FILE_COMMON evidence record.

### 0xbarss/mt5-bridge

Repository:

- `0xbarss/mt5-bridge`

Relevant patterns:

- bounded timer loop by both item count and microsecond time budget;
- event drop/backpressure counters are observable;
- latest-market mode and lossless critical-event mode are distinct;
- offline unit/property testing includes NaN/Infinity, price/tick arithmetic and lot edge cases;
- protocol consistency/fuzzing is tested separately;
- live integration is demo-guarded;
- explicit failure-injection matrix tests disconnects, ambiguous outcomes, partial fills, hedging/netting, idempotency and reconciliation.

Katarina Stage-06 actions:

- timer processing now has count + microsecond budget;
- transport port receives a microsecond budget;
- critical queue exposes high-watermark and rejected-event counters;
- latest-tick slot exposes capture/coalescing counters;
- timer budget exhaustion/max elapsed are observable;
- local execution preflight rejects non-finite values;
- pending/SL/TP prices are checked for broker tick-size alignment;
- duplicate-instance behavior is exercised by the MQL self-test.

Deferred to later frozen stages:

- wire fuzzing → Stage 07/08;
- durable idempotency + UNKNOWN execution failure injection → Stage 18;
- full live integration with broker mutation → Stage 36/38;
- portfolio/multi-symbol integration → Stage 30/31.

### smizxe/mt5-agent-toolkit

Repository:

- `smizxe/mt5-agent-toolkit`

Useful operational failure cases for `terminal64.exe /config:`:

- a running terminal can consume/ignore the command-line test request and produce no report;
- absolute report paths can be silently ignored;
- BOM/encoding mistakes in generated INI files can make tester startup fail in misleading ways.

Katarina decision:

- do not make Stage 06 depend on fragile headless Strategy Tester automation;
- keep Stage-06 proof on explicit MetaEditor compile + actual MQL self-test/account probe;
- when Strategy Tester automation is built in Stage 35, these failure cases become explicit tests/guards.

### psyb0t/mt5-httpapi

Repository:

- `psyb0t/mt5-httpapi`

Relevant operational patterns:

- tester/data directories have single-instance/process-lock implications;
- serialized tester jobs avoid multiple jobs fighting over one terminal data directory;
- terminal/tester process cleanup needs ownership awareness.

Katarina decision:

- defer full terminal/tester process automation to Stage 35;
- Stage 06 keeps its proof procedure simple and avoids process-killing automation.

### FILE_COMMON evidence patterns

Public MQL repositories commonly use `FileOpen(... FILE_COMMON ...)` for machine-readable bridge/event artifacts shared outside one terminal sandbox.

Katarina action:

- Stage-06 MQL self-test and account probe now write evidence to the terminal Common/Files area;
- no password/credential is written;
- account probe requires the human to explicitly label the account `STANDARD_LIKE` or `CENT_LIKE` rather than guessing from a broker marketing convention.

## New Stage-06 Hardening From This Review

### Timer starvation protection

Stage-06 timer now uses:

~~~text
max items
+
max microseconds
~~~

The critical-event drain is always serviced before heavier snapshot work.

Snapshot refresh only begins if:

- critical queue is empty;
- sufficient timer budget remains.

Individual MT5 API calls are not preemptible, so actual maximum elapsed time is measured and reported rather than falsely claiming hard realtime behavior.

### Backpressure observability

Critical queue:

- current count;
- capacity;
- high-watermark;
- rejected total.

Latest tick:

- capture total;
- coalesced replacement total.

Timer:

- budget-exhausted total;
- maximum observed elapsed microseconds.

A critical trade-event rejection still blocks the bridge fail-closed.

### Numeric preflight hardening

Local disabled execution preflight now rejects:

- invalid side;
- NaN/Infinity or otherwise invalid numeric values;
- invalid point/tick-size economics;
- pending/SL/TP prices not aligned to broker tick size.

A valid request still terminates at:

~~~text
KAT_PREFLIGHT_STAGE06_EXECUTION_DISABLED
~~~

No Stage-06 OrderSend path exists.

### Runtime evidence

Self-test evidence:

~~~text
Katarina_Stage06_self_test_result.txt
~~~

Account probes:

~~~text
Katarina_Stage06_account_probe_STANDARD_LIKE.txt
Katarina_Stage06_account_probe_CENT_LIKE.txt
~~~

The records are written under MT5 Common/Files.

Collector:

- `scripts/mt5/collect_stage06_runtime_evidence.ps1`

The collector requires all three records to PASS and combines them with the compile proof into:

- `build/mt5/stage06_runtime_evidence.json`.

## What Is Still Truly Missing

After this GitHub reference audit, no new Stage-06 architecture feature is required before compiler/runtime proof.

Remaining blockers are evidence, not design:

1. actual MetaEditor compile on the modern-Windows baseline;
2. zero errors and zero warnings;
3. fresh EX5 artifacts;
4. actual MQL self-test PASS;
5. standard-like account probe PASS;
6. cent-like account probe PASS;
7. collect runtime evidence;
8. final Stage-06 audit/freeze.

## Intentionally Not Pulled Into Stage 06

The following are important but belong later:

- ZeroMQ/TCP implementation — Stage 07;
- binary protocol fuzzing/cross-language codec tests — Stage 07/08;
- durable execution idempotency — Stage 18;
- UNKNOWN execution reconciliation failure injection — Stage 18;
- full automated Strategy Tester orchestration — Stage 35;
- demo broker mutation integration suite — Stage 36;
- live micro-risk mutation tests — Stage 38.

Pulling these into Stage 06 would mix bridge sensing architecture with later transport/execution responsibilities.

## Result

**Stage-06 source/design gap review: PASS.**

The remaining Stage-06 work is the real Windows/MetaEditor/MT5 evidence gate.
