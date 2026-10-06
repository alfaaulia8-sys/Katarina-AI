# Risk Profile V3 — Unified Across Backtest, Demo and Real

KATARINA uses **one risk profile in every environment**. Backtest, demo and real execution do not have separate numeric risk limits.

## Unified limits

- Maximum risk per entry: **5% of account equity**.
- Maximum aggregate open risk: **8%**.
- Maximum daily drawdown: **10%**.
- At or above 10% daily drawdown, KATARINA pauses new risk until the next trading day.
- Maximum total drawdown hard limit: **20%**.

These values are ceilings, not mandatory trade sizes. KATARINA may approve less than 5% based on uncertainty, open exposure, account state and other risk gates.

## Environment policy

The exact same numeric risk profile is used for:
- backtest;
- strategy tester;
- paper trading;
- demo;
- real/live.

Stage 38 still requires explicit authorization evidence before real execution can be armed. That gate is an **execution authorization gate**, not a different risk model. Once authorized, the same 5% per-entry / 10% daily-DD profile applies.

## Recovery Factor

Recovery Factor remains:

`Recovery Factor = Net Profit / Maximum Drawdown`

It is reported by BacktestingEngine and PerformanceMonitor. It is a quality metric and does not bypass any safety or risk gate.


## Manual and shared-account exposure

Manual, foreign-EA and unknown-origin open positions consume the same 8% aggregate open-risk budget as KATARINA positions. KATARINA prefers broker-native OrderCalcProfit loss-to-SL and falls back to SymbolSpec tick economics. Any open exposure without a quantifiable SL is treated as unbounded and pauses new automated risk.
