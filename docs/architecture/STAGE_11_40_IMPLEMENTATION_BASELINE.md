# Stage 11-40 Implementation Baseline

This document records the VPS implementation baseline for the remaining KATARINA roadmap.

## Authority boundary

The frozen Constitution and Stages 01-09 remain authoritative. No later stage may:
- arm execution without the explicit execution gate;
- bypass the Risk Governor;
- change the Constitution autonomously;
- use live capital as a research environment;
- convert unknown/stale/unreconciled state into permission to add risk.

## Implemented baseline

- Stage 11 Market Intelligence: deterministic market feature extraction.
- Stage 12 Multi-Timeframe: freshness-aware alignment assessment.
- Stage 13 Market Regime: trend/range/high-vol/unknown classification with OOD flag.
- Stage 14 XAUUSD Specialist V1: XAUUSD-specific evidence scoring and safe-domain checks.
- Stage 15 Decision Engine: BUY/SELL/NO_TRADE/WAIT/SAFE_MODE candidates, never live authorization.
- Stage 16 Risk Governor: deterministic hard caps and fail-closed pause/reject semantics.
- Stage 17 Position Sizing: deterministic stop/risk/value-based sizing with broker-volume constraints.
- Stage 18 Execution Engine: lineage, preflight, idempotent intent reservation; no direct broker adapter.
- Stage 19 Position Manager: broker-state-driven hold/protect/close decisions.
- Stage 20 Trade Evaluation: R, MAE/MFE, costs and decision-quality measurement.
- Stage 21 Research Engine: read-only hypothesis generation.
- Stage 22 Backtesting: cost-aware deterministic trade evaluation.
- Stage 23 OOS / Walk-Forward: non-overlapping train/test windows.
- Stage 24 Monte Carlo: seeded robustness and drawdown estimates.
- Stage 25 Shadow Katarina: candidate/production comparison without broker mutation.
- Stage 26 Learning: drift detection and candidate generation only.
- Stage 27 ML V1: deterministic lightweight logistic baseline.
- Stage 28 Model Promotion/Rollback: all-gates promotion and explicit rollback.
- Stage 29 Economic Intelligence: event-context and high-impact blackout logic.
- Stage 30 Portfolio/Multi-Pair: aggregate risk-cap allocation.
- Stage 31 Correlation/Exposure: correlation-adjusted global risk.
- Stage 32 Dashboard: read-only state serialization.
- Stage 33 Automated Testing/CI: fail-closed required-suite policy.
- Stage 34 Constitution Guard: digest verification and forbidden autonomous mutation targets.
- Stage 35 Strategy Tester: deterministic tester transport/replay.
- Stage 36 Paper/Demo: paper execution venue with explicit cost/slippage assumptions.
- Stage 37 Stress Test: disconnect/latency/spread/data-failure risk blocking.
- Stage 38 Live Validation: explicit human + demo + broker + reconciliation + stress + monitoring gates. Once authorized, it uses the same unified 5% per-entry risk ceiling as backtest and demo.
- Stage 39 Performance Monitoring: expectancy, drawdown, win rate and degradation state.
- Stage 40 Continuous Evolution: research -> validation -> shadow -> promotion review; autonomous live promotion remains prohibited.

## Important limitation

"Implementation baseline ready" is not the same as "live capital validated". Stage 36 and Stage 38 require real external evidence before any live-capital readiness claim can be made.
