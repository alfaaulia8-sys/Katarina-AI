# Katarina AI Build Roadmap

| # | Stage | Status |
|---|---|---|
| 01 | Constitution & North Star | ✅ FINALIZED / FROZEN v1.1.0 |
| 02 | Final MT5-to-Execution Workflow | ✅ FINALIZED / FROZEN v1.2.0 |
| 03 | Repository Architecture | ✅ FINALIZED / FROZEN v1.0.0 |
| 04 | Data Protocol / Schemas | ✅ FINALIZED / FROZEN — KAT1 v1.0.0 |
| 05 | Katarina Core / Orchestrator | ⏳ NEXT |
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

**04/40 completed. Stage 05 — Katarina Core / Orchestrator — is next.**

## Frozen Stage 04 Scope

KAT1 v1.0.0 now freezes:

- canonical little-endian binary framing;
- exact 30-message registry and payload layouts;
- scaled execution-sensitive numeric representation;
- explicit identity/revision binding;
- standard + cent account-native handling;
- shared-account/manual-trade learning visibility;
- Hedging + Netting account support;
- MARKET + LIMIT + STOP entries;
- mandatory broker-native SL for Katarina exposure;
- first-class account ledger;
- chunked atomic snapshots;
- CRC32C/conformance rules;
- 13 canonical golden vectors.
