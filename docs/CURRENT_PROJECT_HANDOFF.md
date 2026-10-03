# Katarina AI — Current Project Handoff

**Updated:** 2026-10-03
**Purpose:** Persistent cross-chat handoff for continuing development after a chat is deleted or replaced.

## Current roadmap position

- Stage 01 — Constitution & North Star: FROZEN
- Stage 02 — MT5-to-Execution Workflow: FROZEN
- Stage 03 — Repository Architecture: FROZEN
- Stage 04 — KAT1 Data Protocol / Schemas: FROZEN v1.0.0
- Stage 05 — Katarina Core / Orchestrator: FROZEN
- Stage 06 — MT5 Bridge EA: implementation + clearance automation complete; external MetaEditor/MT5 proof still pending
- Stage 07 — MT5 ↔ Python Communication: research/design active; Python conformance work started; production MQL5 transport integration gated on Stage-06 proof

## VPS bridge status

Implementation status: **READY FOR VPS INSTALLATION / FIRST LIVE TELEMETRY TEST**

- Repository-driven bridge is implemented.
- Windows Server 2012 R2 uses the legacy outbound-HTTPS PowerShell polling agent, not the unsupported GitHub Actions runner.
- Legacy agent version: **1.1.0**.
- Request execution is allowlisted; arbitrary shell commands are not accepted.
- Request target, schema, request-id/filename binding, expiry, task allowlist, and Git ref are validated before repository snapshot execution.
- Processed request IDs use exact matching to prevent collisions such as `req-001` vs `req-0010`.
- Malformed request files are isolated per item so one bad request does not block later valid requests.
- Results remain text-only and secret-redacted before upload.
- No inbound VPS command port is required.

Remaining live bridge gate:

1. install `scripts/vps/legacy/Install-KatarinaVpsAgent.ps1` on the real Windows Server 2012 R2 VPS;
2. confirm the scheduled task `KatarinaVPSAgent` starts;
3. submit one `HOST_INVENTORY` request targeted to `katarina-vps-2012r2-01`;
4. verify the VPS writes the result into `ops/vps/results/<agent>/<request>/`;
5. use that evidence to decide the Python/MT5 compatibility path.

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

Stage-06 remaining external proof gates:

1. actual MetaEditor compile on supported modern Windows
2. actual MQL self-test in MT5
3. actual STANDARD_LIKE account probe
4. actual CENT_LIKE account probe
5. actual runtime evidence collection
6. governed final Stage-06 audit/freeze

Windows Server 2012 R2 is deferred and is not a Stage-06 freeze blocker.

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

Install the already-implemented legacy Katarina VPS Agent on the real Windows Server 2012 R2 host, then run the first read-only `HOST_INVENTORY` request.

Expected flow:

GitHub repository
→ legacy Windows Server 2012 R2 polling agent over outbound HTTPS
→ allowlisted host inventory/test task
→ redacted text evidence
→ `ops/vps/results/<agent>/<request>/`
→ ChatGPT reviews the evidence and applies the next repository change

For modern Windows validation hosts, the repository also retains the GitHub Actions self-hosted runner workflow.

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
