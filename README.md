# Katarina-AI

Katarina AI is being rebuilt as a **central financial intelligence system** for data-driven, adaptive, risk-governed trading.

## Current Build Position

- Stage 01 — Constitution & North Star: ✅ FROZEN v1.1.0
- Stage 02 — MT5-to-Execution Workflow: ✅ FROZEN v1.2.0
- Stage 03 — Repository Architecture: ✅ FROZEN v1.0.0
- Stage 04 — Data Protocol / Schemas: ✅ FROZEN — KAT1 v1.0.0
- Stage 05 — Katarina Core / Orchestrator: ✅ FROZEN — v1.0.0
- Stage 06 — MT5 Bridge EA: ✅ FROZEN v1.0.0 — Bridge design v0.5.0
- Stage 07 — MT5 ↔ Python Communication: ✅ FROZEN v1.0.0 — `PASS_STAGE07_FINAL_CLEARANCE`
- Stage 08 — Data Validation Engine: ✅ FROZEN v1.0.0 — `PASS_STAGE08_FINAL_CLEARANCE`
- Stage 09 — Health & Safety Engine: ✅ FROZEN v1.0.0 — `PASS_STAGE09_FINAL_CLEARANCE`
- Stage 10 — Database & Memory V1: 🟡 IMPLEMENTATION ACTIVE

## KAT1 v1.0.0

KAT1 is the canonical binary MT5 ↔ Katarina protocol.

~~~text
MT5 / Katarina logical message
        ↓
KAT1 explicit schema
        ↓
canonical little-endian bytes
        ↓
ZeroMQ / TCP / TesterTransport
~~~

Frozen properties:

- fixed 52-byte frame header;
- explicit message type, schema version and block length;
- 30 registered message types with exact layouts;
- stream_id, boot_id and sequence;
- scaled int64 for execution-sensitive price/volume/money values;
- 128-bit lineage IDs;
- max frame bound 65,536 bytes;
- CRC32C for critical/durable frames;
- instrument dictionary + SymbolSpec revisions;
- transactional chunked snapshots;
- durable execution/reconciliation semantics;
- shared-account/manual-trade observation;
- Hedging + Netting support;
- MARKET + LIMIT + STOP entries;
- broker-native SL required for Katarina-created exposure;
- standard + cent account-native normalization;
- first-class deposit/withdrawal/credit/balance ledger;
- Python/MQL5 golden conformance contract.

## Canonical Stage 04 Documents

- [KAT1 Protocol V1](docs/architecture/KATARINA_BINARY_PROTOCOL_V1.md)
- [KAT1 Data Contract V1](docs/architecture/KAT1_DATA_CONTRACT_V1.md)
- [KAT1 Conformance V1](docs/architecture/KAT1_CONFORMANCE_V1.md)
- [Hedging / Netting Contract](docs/architecture/KAT1_HEDGING_NETTING_EXECUTION.md)
- [Standard / Cent Compatibility](docs/architecture/STANDARD_CENT_ACCOUNT_COMPATIBILITY.md)
- [Manual Trade Learning V1](docs/architecture/MANUAL_TRADE_LEARNING_CONTRACT_V1.md)
- [Stage 04 Audit](docs/reviews/STAGE_04_PROTOCOL_AUDIT.md)

Machine-readable contracts:

- [Protocol Config](config/protocol_schema.json)
- [Message Registry](protocol/message_registry_v1.json)
- [Exact Schemas](protocol/kat1_message_schemas_v1.json)
- [Enums](protocol/enums_v1.json)
- [Flags](protocol/flags_v1.json)
- [Capabilities](protocol/capabilities_v1.json)
- [Reason Codes](protocol/reason_codes_v1.json)
- [Payload Catalog](protocol/payload_catalog_v1.json)
- [Golden Vectors](protocol/golden/kat1_v1_vectors.json)

## Canonical Project Documents

- [KATARINA_CONSTITUTION.md](KATARINA_CONSTITUTION.md)
- [docs/KATARINA_FINAL_WORKFLOW.md](docs/KATARINA_FINAL_WORKFLOW.md)
- [docs/architecture/REPOSITORY_ARCHITECTURE.md](docs/architecture/REPOSITORY_ARCHITECTURE.md)
- [docs/BUILD_ROADMAP.md](docs/BUILD_ROADMAP.md)


## Stage 05 — Core / Orchestrator v1.0.0

The first Katarina runtime core is now implemented as a standard-library Python skeleton.

```text
adapters / future KAT1 decode
        ↓
immutable EventEnvelope
        ↓
bounded priority ingress
        ↓
KatarinaOrchestrator
        ↓
deterministic serial EventBus
        ↓
started components only
        ↓
new events return to ingress
```

Important safety properties:

- one authoritative mutation lane;
- runtime components do not receive recovery traffic before they start;
- component dependencies are topologically validated;
- critical ingress overflow faults fail-closed;
- live execution arming resets on boot/fault;
- `RUNNING` does not imply permission to open live risk;
- shared Core design remains compatible with Live / Tester / Shadow / Research.

Stage 05 documents:

- [Core / Orchestrator V1](docs/architecture/KATARINA_CORE_ORCHESTRATOR_V1.md)
- [Stage 05 Research](docs/reviews/STAGE_05_CORE_RESEARCH.md)
- [Core Config](config/core_orchestrator.json)

Current implementation:

- `src/katarina/contracts/runtime.py`
- `src/katarina/core/lifecycle.py`
- `src/katarina/core/component.py`
- `src/katarina/core/message_bus.py`
- `src/katarina/core/queue.py`
- `src/katarina/core/readiness.py`
- `src/katarina/core/state.py`
- `src/katarina/core/orchestrator.py`

Unit tests:

- `tests/unit/core/test_stage05_core.py`

Stage 05 passed final audit and is **FROZEN v1.0.0**. See [Stage 05 Audit](docs/reviews/STAGE_05_CORE_AUDIT.md).


## Stage 06 — MT5 Bridge EA (In Review)

The MT5-side bridge has started as a read-only, fail-closed sensor/gateway skeleton.

```text
MT5 events
   ↓
fast capture
   ↓
bounded local buffers
   ↓
transport-neutral port
   ↓
Stage-07 communication later
```

Current safety properties:

- no discretionary BUY/SELL logic in MQL5;
- no OrderSend path is enabled yet;
- startup never auto-arms execution;
- OnTick is capture-only;
- OnTradeTransaction is capture/enqueue-only;
- critical trade-event overflow blocks future risk;
- account/symbol facts are broker-native, supporting standard/cent design;
- complete account/position/order snapshot source exists;
- local duplicate-instance lease exists;
- manual order/deal/position reasons are preserved;
- broker session/health, bar, deal-history and broker-calc sources exist;
- MARKET/LIMIT/STOP preflight exists but always ends execution-disabled in Stage 06;
- bridge stays RECOVERING until complete transport/journal/reconciliation readiness exists.

Stage 06 documents:

- [MT5 Bridge Architecture Draft](docs/architecture/KATARINA_MT5_BRIDGE_DRAFT.md)
- [Stage 06 Research](docs/reviews/STAGE_06_MT5_BRIDGE_RESEARCH.md)
- [MT5 Bridge Config Draft](config/mt5_bridge_draft.json)
- [KAT1 → MT5 Field Source Mapping](docs/architecture/KAT1_MT5_FIELD_SOURCE_MAPPING_DRAFT.md)
- [Stage 06 Compile Proof](docs/operations/STAGE_06_MT5_COMPILE_PROOF.md)
- [Stage 06 Windows Compatibility](docs/operations/STAGE_06_WINDOWS_COMPATIBILITY.md)
- [Stage 06 GitHub Reference Audit](docs/reviews/STAGE_06_GITHUB_REFERENCE_AUDIT.md)
- [Stage 06 Final Clearance](docs/operations/STAGE_06_FINAL_CLEARANCE.md)

Prepared verification:

- `mt5/Tests/KatarinaStage06SelfTest.mq5`
- `mt5/Tests/KatarinaStage06AccountProbe.mq5`
- `tests/static/test_stage06_mt5_bridge.py`
- `scripts/mt5/compile_stage06.ps1`
- `scripts/mt5/check_stage06_host.ps1`
- `scripts/mt5/verify_stage06_modern_windows.ps1`
- `tests/static/test_stage06_windows_compatibility.py`
- `scripts/mt5/collect_stage06_runtime_evidence.ps1`
- `scripts/mt5/audit_stage06_final.ps1`
- `scripts/mt5/complete_stage06.ps1`

Stage 06 implementation and clearance automation are complete. Freeze now depends only on externally generated evidence from a modern 64-bit Windows + MT5/MetaEditor environment: strict compile proof, MQL self-test, standard-like probe, cent-like probe, runtime-evidence collection, and governed final review. Windows Server 2012 R2 is deliberately deferred.


### Current Windows validation baseline

Preferred:

- Windows Server 2022 x64
- Windows 11 x64

Compatibility validation:

- Windows Server 2019 x64
- Windows Server 2016 x64
- Windows 10 x64

Deferred:

- Windows Server 2012 R2 x64

The modern compile proof requires zero errors, zero warnings, fresh non-empty EX5 artifacts, and SHA-256 evidence. See `docs/operations/STAGE_06_WINDOWS_COMPATIBILITY.md`.


## Stage 07 — MT5 ↔ Python Communication (Frozen v1.0.0)

Final clearance: `PASS_STAGE07_FINAL_CLEARANCE` on run `37209799384`.

Frozen outcomes include ZeroMQ primary transport, native TCP fallback, exact KAT1 byte equality, recovery/reconciliation, reconnect sequence continuity, and bounded backpressure. Live risk remains disabled.

See `docs/reviews/STAGE_07_FREEZE_RECORD.md`.

## Stage 08 — Data Validation Engine (Frozen v1.0.0)

Stage 08 is finalized under `PASS_STAGE08_FINAL_CLEARANCE`.

Frozen outcomes include canonical KAT1 semantic validation, SymbolSpec binding, history completeness, per-class freshness, account/position/order validation, ACCEPT/QUARANTINE/REJECT promotion control, and DATA_FRESH-only readiness authority.

Evidence run: `37211163352` — 37/37 tests PASS. Live risk remained disabled.

See `docs/reviews/STAGE_08_FREEZE_RECORD.md`.

## Stage 09 — Health & Safety Engine (Frozen v1.0.0)

Stage 09 is finalized under `PASS_STAGE09_FINAL_CLEARANCE`.

Frozen outcomes include KAT1 health aggregation, stale-heartbeat protection, queue-pressure gates, clock/session/transport health, recovery hysteresis, and HEALTH-only readiness authority.

Evidence run: `37211508723` — 20/20 tests PASS. Live risk remained disabled.

See `docs/reviews/STAGE_09_FREEZE_RECORD.md`.

## Stage 10 — Database & Memory V1

Stage 10 is active. It will establish durable operational records and memory boundaries while preserving deterministic replay and fail-closed recovery.

## VPS Remote Lab Bridge

A controlled repository-mediated VPS bridge is prepared before further Stage-07 integration.

Current paths:

- modern Windows: GitHub Actions self-hosted runner through `.github/workflows/katarina-vps-lab.yml`;
- Windows Server 2012 R2: outbound-only PowerShell polling agent under `scripts/vps/legacy/`.

Security baseline:

- no inbound command port;
- no arbitrary shell command in request JSON;
- fixed allowlisted task IDs only;
- target-agent and expiry validation;
- DPAPI-protected legacy token;
- text-only result relay;
- no production broker mutation.

See `docs/operations/KATARINA_VPS_REMOTE_LAB.md`.
