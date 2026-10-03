# Katarina AI — Current Project Handoff

**Updated:** 2026-10-03
**Purpose:** Persistent cross-chat handoff for continuing development after a chat is deleted or replaced.

## Current roadmap position

- Stage 01 — Constitution & North Star: FROZEN
- Stage 02 — MT5-to-Execution Workflow: FROZEN
- Stage 03 — Repository Architecture: FROZEN
- Stage 04 — KAT1 Data Protocol / Schemas: FROZEN v1.0.0
- Stage 05 — Katarina Core / Orchestrator: FROZEN
- Stage 06 — MT5 Bridge EA: implementation + clearance automation complete; legacy external MetaEditor compile proof PASSED on Windows Server 2012 R2 (0 errors / 0 warnings for Bridge EA, SelfTest, AccountProbe), but supported-modern-host freeze proof and MT5 runtime probes are still pending
- Stage 07 — MT5 ↔ Python Communication: research/design active; Python conformance work started; production MQL5 transport integration gated on Stage-06 proof

## VPS bridge status

Implementation status: **LIVE END-TO-END CONNECTED**

- Agent: `katarina-vps-2012r2-01`.
- Windows Server 2012 R2 uses the legacy outbound-HTTPS PowerShell polling agent.
- ChatGPT → GitHub request queue → VPS task execution → GitHub result write-back has been proven with multiple `HOST_INVENTORY` requests.
- Agent v1.2.2 is currently running successfully; repository source is v1.2.3 with shortened local work paths for the Windows 260-character path limit.
- Request execution remains allowlisted; arbitrary shell commands are not accepted.
- Results remain text-only and secret-redacted before upload.
- No inbound VPS command port is required.
- Deep host discovery is enabled.

Detected on the real VPS:

- Windows Server 2012 R2 Standard x64
- PowerShell 4.0
- MetaTrader 5 ALFA:
  - `C:\Program Files\MetaTrader 5 ALFA\terminal64.exe`
  - `C:\Program Files\MetaTrader 5 ALFA\metaeditor64.exe`
- MetaTrader 5 generic / MetaQuotes:
  - `C:\Program Files\MetaTrader 5\terminal64.exe`
  - `C:\Program Files\MetaTrader 5\metaeditor64.exe`
- Two valid MT5 terminal data folders with `MQL5` and `Tester`.
- MT5 Common data path detected under the Administrator profile.
- Python executable: not detected.
- Git CLI: not detected.

Operational note:

- Long request IDs can trigger the Windows Server 2012 R2 legacy MAX_PATH limit in the currently installed v1.2.2 agent. Short request IDs work. Repository agent v1.2.3 hashes request IDs into short local work-directory names; install source on the VPS at the next maintenance update.

## Stage 06 final status

Design version: v0.5.0

Implemented:

- transport-neutral MT5 bridge
- fail-closed lifecycle
- account / position / order snapshot
- manual trade evidence
- standard-like + cent-like broker-native facts
- hedging + netting support boundaries
- MARKET / LIMIT / STOP preflight
- mandatory native SL
- duplicate-instance guard
- persistent stream_id + per-boot boot_id
- type-aware MqlTradeTransaction capture
- health/session facts
- broker calc source
- bar source
- deal history source
- bounded timer work
- backpressure metrics
- numeric / tick-grid preflight
- runtime evidence writer
- Windows modern compatibility baseline
- GitHub reference audit
- compile/runtime/final-clearance automation

Important Stage-06 scripts:

- scripts/mt5/check_stage06_host.ps1
- scripts/mt5/compile_stage06.ps1
- scripts/mt5/verify_stage06_modern_windows.ps1
- scripts/mt5/collect_stage06_runtime_evidence.ps1
- scripts/mt5/audit_stage06_final.ps1
- scripts/mt5/complete_stage06.ps1

Stage-06 proof files expected:

- build/mt5/stage06_compile_evidence.json
- build/mt5/stage06_runtime_evidence.json
- build/mt5/stage06_final_clearance.json
- build/mt5/STAGE_06_FINAL_AUDIT_CANDIDATE.md

Stage-06 runtime evidence files:

- Katarina_Stage06_self_test_result.txt
- Katarina_Stage06_account_probe_STANDARD_LIKE.txt
- Katarina_Stage06_account_probe_CENT_LIKE.txt

Stage-06 evidence achieved on the real 2012 R2 VPS:

- MetaEditor 5.0.0.6230 discovered and invoked successfully.
- Exploratory compile result: `PASS_LEGACY_COMPILE_NOT_FREEZE_PROOF`.
- `KatarinaBridgeEA.mq5`: 0 errors, 0 warnings, EX5 created.
- `KatarinaStage06SelfTest.mq5`: 0 errors, 0 warnings, EX5 created.
- `KatarinaStage06AccountProbe.mq5`: 0 errors, 0 warnings, EX5 created.
- Compile evidence is source-hash bound.
- MQL executable version metadata was normalized to `1.000` to satisfy MetaEditor warning-68 rules; Stage-06 bridge design version remains `0.5.0`.

Stage-06 remaining external proof gates:

1. repeat strict compile proof on a supported modern Windows validation host
2. actual MQL self-test in MT5
3. actual STANDARD_LIKE account probe
4. actual CENT_LIKE account probe
5. actual runtime evidence collection
6. governed final Stage-06 audit/freeze

Windows Server 2012 R2 is DEFERRED: it is useful for exploratory compile/runtime diagnostics, but evidence from this host is not freeze-qualified. A supported modern Windows validation host is still required for Stage-06 freeze.

Preferred validation hosts:

- Windows Server 2022 x64
- Windows 11 x64

## Stage 07 current status

Research/design completed or started:

- GitHub prior-art review
- localhost ZeroMQ topology draft
- Python ROUTER / MT5 DEALER draft
- native localhost TCP fallback design
- heartbeat / reconnect design
- TransportPort abstraction
- Python schema-driven KAT1 codec
- bounded in-memory transport adapter
- Stage-04 golden-vector round-trip tests
- ADR-0009 proposed

Stage-07 files:

- docs/reviews/STAGE_07_COMMUNICATION_RESEARCH.md
- docs/reviews/STAGE_07_INITIAL_IMPLEMENTATION_CHECK.md
- docs/architecture/KATARINA_MT5_PYTHON_COMMUNICATION_DRAFT.md
- docs/adr/0009-stage07-live-communication-topology.md
- config/mt5_python_communication_draft.json
- src/katarina/ports/transport.py
- src/katarina/adapters/transport/kat1_codec.py
- src/katarina/adapters/transport/memory.py
- tests/unit/transport/test_stage07_communication.py

Stage-07 production MQL5 ZeroMQ/TCP integration must NOT modify the Stage-06 MQL clearance candidate until Stage 06 has real external proof/freeze.

## Next recommended action

Use the already-compiled Stage-06 artifacts on the detected MT5 instance to obtain runtime evidence:

1. run `KatarinaStage06SelfTest` inside MT5;
2. run `KatarinaStage06AccountProbe` on a STANDARD_LIKE account;
3. run `KatarinaStage06AccountProbe` on a CENT_LIKE account;
4. collect the three proof files from MT5 Common Files;
5. keep the resulting runtime evidence as exploratory 2012 R2 evidence;
6. separately repeat the strict compile/runtime proof on a supported modern Windows host before Stage-06 freeze.

The VPS bridge itself is operational and can now be used for repository tests, Stage-06 diagnostics, Stage-07 Python tests when Python becomes available, and MT5 log collection.

Do not put passwords, VPS credentials, API keys, broker passwords, PATs, or private account credentials into the repository or chat.

## Project invariant reminders

- Python is the central intelligence.
- MT5 is sensor + deterministic safety + execution/reporting layer.
- MT5 does not invent discretionary BUY/SELL decisions.
- NO TRADE is a valid decision.
- Risk Governor is absolute.
- live-risk readiness is separate from transport connectivity.
- Stage 04 KAT1 is authoritative.
- Stage 06 remains fail-closed until real proof is complete.
