# Katarina AI Build Roadmap

| # | Stage | Status |
|---|---|---|
| 01 | Constitution & North Star | ✅ FINALIZED / FROZEN v1.1.0 |
| 02 | Final MT5-to-Execution Workflow | 🟡 IN REVIEW — binary transport policy approved |
| 03 | Repository Architecture | ⬜ |
| 04 | Data Protocol / Schemas | ⬜ |
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

**Stage 02 is active.**

Approved Stage 02 decisions so far:

- event-driven delta transport rather than full-state resend on every tick;
- Katarina-side state cache and immutable decision snapshots;
- production hot path uses versioned binary from day one;
- JSON is for audit/debug, not authoritative realtime transport;
- transport abstraction separates Brain from ZeroMQ/TCP/tester implementation;
- live primary transport: ZeroMQ localhost;
- live fallback transport: native local TCP;
- Strategy Tester uses a dedicated TesterTransport adapter;
- actual broker transaction lifecycle is separated from position lifecycle;
- end-to-end IDs and latency observability are required.

Stage 02 remains open for further sweeping before final freeze.
