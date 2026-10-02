# Katarina AI Build Roadmap

| # | Stage | Status |
|---|---|---|
| 01 | Constitution & North Star | ✅ FINALIZED / FROZEN v1.1.0 |
| 02 | Final MT5-to-Execution Workflow | ✅ FINALIZED / FROZEN v1.2.0 |
| 03 | Repository Architecture | ✅ FINALIZED / FROZEN v1.0.0 |
| 04 | Data Protocol / Schemas | 🟡 IN REVIEW — KAT1 draft 0.2 / OWNER DECISIONS |
| 05 | Katarina Core / Orchestrator | ⬜ |
| 06 | MT5 Bridge EA | ⬜ |
| 07 | MT5-Python Communication | ⬜ |
| 08 | Data Validation Engine | ⬜ |
| 09 | Health & Safety Engine | ⬜ |
| 10 | Database & Memory V1 | ⬜ |
| 11 | Market Intelligence Engine | ⬜ |
| 12 | Multi-Timeframe Engine | ⬜ |
| 13 | Market Regime Engine | ⬜ |
| 14 | XAUUSD Specialist V1 | ⬜ |
| 15 | Decision Engine | ⬜ |
| 16 | Risk Governor | ⬜ |
| 17 | Position Sizing Engine | ⬜ |
| 18 | Execution Engine | ⬜ |
| 19 | Position Manager | ⬜ |
| 20 | Trade Evaluation Engine | ⬜ |
| 21 | Research Engine | ⬜ |
| 22 | Backtesting Engine | ⬜ |
| 23 | Out-of-Sample + Walk-Forward | ⬜ |
| 24 | Monte Carlo / Robustness | ⬜ |
| 25 | Shadow Katarina | ⬜ |
| 26 | Learning Engine | ⬜ |
| 27 | Machine Learning V1 | ⬜ |
| 28 | Model Promotion & Rollback | ⬜ |
| 29 | Economic Intelligence Engine | ⬜ |
| 30 | Portfolio & Multi-Pair Engine | ⬜ |
| 31 | Correlation & Global Exposure Engine | ⬜ |
| 32 | Dashboard | ⬜ |
| 33 | Automated Testing / CI | ⬜ |
| 34 | Constitution Guard | ⬜ |
| 35 | MT5 Strategy Tester Integration | ⬜ |
| 36 | Paper / Demo Trading | ⬜ |
| 37 | Stress Test | ⬜ |
| 38 | Live Micro-Risk Validation | ⬜ |
| 39 | Performance Monitoring | ⬜ |
| 40 | Continuous Evolution | ⬜ |

## Current Position

**Stage 04 is active and in review.**

Current draft decisions:

- MT5 sends broker facts; Python/Katarina derives intelligence;
- TickEvent fixed body draft: 48 bytes;
- BarEvent fixed body draft: 80 bytes;
- full SymbolSpec / account / position / order / execution data catalog drafted;
- six owner operating decisions remain before schema freeze;

- KAT1 custom canonical binary;
- SBE-inspired fixed root blocks;
- explicit little-endian encoding;
- no raw native-struct wire contract;
- scaled int64 for execution-sensitive decimal values;
- 128-bit trace IDs;
- instrument dictionary + spec revision;
- 65,536-byte frame bound;
- chunked atomic snapshots;
- strict schema evolution;
- Python/MQL5 golden conformance fixtures required before freeze.
