# KATARINA Stage 16/17 — Broker-cost and margin research qualifier

Date: 11 October 2026. **Research-only; not approved for live trading.**

## Why this matters
The original PositionSizingEngine handles nominal stop risk but does not independently enforce all broker spread, adverse slippage, round-trip fees and remaining margin. The new isolated ResearchCostMarginGate refuses a research-sized position if any required risk, contract or execution-cost evidence is unverified.

## Fail-closed contract
- Requires *explicitly verified* account facts, contract revision, native money units and execution cost assumptions. A symbol suffix alone cannot verify USD vs USC.
- Requires signal uncertainty and expected reward:risk values; an absent or unacceptable signal is rejected by the existing RiskGovernor.
- Applies existing adaptive RiskGovernor settings, open risk, daily/total drawdown, health and reconciliation; no limits increased.
- Requires directional stop-loss on the correct side. Includes spread buffer, slippage buffer and round-trip fees in maximum modeled stop loss.
- Floors allowed size to the instrument's min-volume plus volume-step grid. Never rounds a too-large minimum lot upward.
- Caps modeled margin use at 90% of available margin, then checks both margin and buffered stop loss against caps.
- Is disconnected from MT5 order submission and always returns live_execution_authorized=False.

## Synthetic tests and evidence
Unit tests verify USD 100 / 1,000 / 10,000 account examples, minimum lot rejection, cost/margin stress, missing signals, buy/sell stop geometry, drawdown, correlated or unknown exposures and synthetic USC denomination. CI emits build/validation/stage16-17-synthetic.json. Broker facts with verified=True **in synthetic fixtures** are not evidence of a verified real account.

## Remaining approvals
Stage 14/15 independent long/short no-lookahead strategy edge and real broker-cost evidence; Stage 16/17 production-level contract verification, tick loss conversion, margin schedule and shared account exposure reconciliation; Stage 35 isolated tester run; Stage 36 read-only broker preflight; Stage 38 explicitly authorized controlled micro-risk test with rollback. None of these gates is cleared by this synthetic test. **Live execution stays disabled.**
