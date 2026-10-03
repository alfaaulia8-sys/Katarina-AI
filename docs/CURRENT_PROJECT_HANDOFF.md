# Katarina AI — Current Project Handoff

**Updated:** 2026-10-03
**Purpose:** Persistent cross-chat handoff for continuing development after a chat is deleted or replaced.

## Current roadmap position

- Stage 01 — Constitution & North Star: FROZEN
- Stage 02 — MT5-to-Execution Workflow: FROZEN
- Stage 03 — Repository Architecture: FROZEN
- Stage 04 — KAT1 Data Protocol / Schemas: FROZEN v1.0.0
- Stage 05 — Katarina Core / Orchestrator: FROZEN
- Stage 06 — MT5 Bridge EA: FINALIZED / FROZEN v1.0.0; Bridge design v0.5.0; governed Windows Server 2022 compile + MQL self-test + final audit PASS
- Stage 07 — MT5 ↔ Python Communication: IMPLEMENTATION ACTIVE; Python session/TCP PASS; MQL5 KAT1 13-vector PASS; ZeroMQ ROUTER↔DEALER PASS; cross-language HEARTBEAT→HELLO→HELLO_ACK PASS

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

Status: **FINALIZED / FROZEN v1.0.0**  
Bridge design: **v0.5.0**

Governed freeze evidence:

- freeze-qualified host: Windows Server 2022 x64
- host class: PREFERRED
- GitHub Actions run: `37139117641`
- evidence head SHA: `4e4f27461bb77e1bcf61fd707f649dc0dfe74def`
- MetaEditor: 5.0.0.6235
- `KatarinaBridgeEA.mq5`: 0 errors / 0 warnings / EX5 created
- `KatarinaStage06SelfTest.mq5`: 0 errors / 0 warnings / EX5 created
- `KatarinaStage06AccountProbe.mq5`: 0 errors / 0 warnings / EX5 created
- modern-host MQL self-test: PASS
- Stage-06 static regressions: 35/35 PASS
- complete MQL source-manifest binding: PASS
- final audit result: `PASS_STAGE06_FINAL_CLEARANCE`
- freeze artifact: `stage06-final-freeze-evidence`
- artifact digest: `sha256:1157e48bb8f84cf15536bb74e64673446017efc4d7461737a8d34d8c31da03fc`
- permanent freeze record: `docs/reviews/STAGE_06_FREEZE_RECORD.md`

Account-compatibility boundary:

- real STANDARD_LIKE broker validation: deferred to Stage 36/38
- real CENT_LIKE broker validation: deferred to Stage 36/38
- this is intentional under ADR-0010 and the frozen Stage-04 contract
- Stage 06 makes no broker-by-broker production compatibility claim

2012 R2 exploratory evidence remains useful but is not freeze-qualified:

- both MT5 installations compile Stage-06 MQL with 0 errors / 0 warnings
- auto gold-symbol discovery resolved `XAUUSD.vx`
- both MT5 terminals currently expose the same saved Valetax account identity, so automatic STANDARD/CENT classification correctly stops as ambiguous
- this ambiguity is not a Stage-06 freeze blocker

Windows Server 2012 R2 remains DEFERRED for freeze proof.

## Stage 07 current status

Research/design completed or started:

- Python fail-closed session supervisor PASS (presence → HELLO → HELLO_ACK → RECOVERING → READY only after explicit recovery);
- stale/reconnect handshake regression PASS;
- same-stream account rebinding fail-closed regression PASS;
- localhost-only native TCP KAT1 framing PASS on Python side;
- MQL5 KAT1 header + CRC32C codec baseline compiled 0 errors / 0 warnings;
- MQL5 13/13 frozen golden vectors PASS on Windows Server 2022;
- ZeroMQ capability + production DEALER byte adapter PASS on Windows Server 2022;
- Python ROUTER adapter localhost integration PASS;
- cross-language HEARTBEAT → HELLO → HELLO_ACK PASS;
- handshake ends RECOVERING, communication_ready=false, live_risk_ready=false as required;

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

Stage-06 is now frozen. Stage-07 production MQL5 ZeroMQ/TCP transport implementation may proceed against the frozen Bridge v0.5.0 contract. Any change to frozen Stage-06 behavior requires explicit governed review.

## Next recommended action

Proceed with Stage 07 — MT5 ↔ Python Communication:

1. implement snapshot + reconciliation recovery gate before communication READY;
2. complete full MQL5 payload codec / cross-language byte-equality beyond system messages;
3. implement MQL5 native TCP fallback against the proven Python server;
4. prove cross-language stale/disconnect/reconnect behavior;
5. profile round-trip latency/backpressure and timer budgets;
6. keep Strategy Tester transport for Stage 35;
7. keep live broker-risk enablement disabled until later governed stages.

The VPS bridge remains available for diagnostics, repository tests, MT5 compilation/log collection and later Stage-07 runtime checks.

## Project invariant reminders

- Python is the central intelligence.
- MT5 is sensor + deterministic safety + execution/reporting layer.
- MT5 does not invent discretionary BUY/SELL decisions.
- NO TRADE is a valid decision.
- Risk Governor is absolute.
- live-risk readiness is separate from transport connectivity.
- Stage 04 KAT1 is authoritative.
- Stage 06 is frozen and remains fail-closed by contract; later stages must not weaken its safety invariants.
