# Owner Decision Addendum — 14 October 2026

Status: **Owner-approved design instructions for offline engineering**. NOT proof of implementation, broker validation, or authorization to trade live.

## Precedence
This addendum records the latest explicit Owner decisions. Preserve the existing, more specific policy where these instructions do not provide numerical implementation parameters. Review deviations before changing risk or production behavior.

### D1 — Deposit / withdrawal, Profit Lock and HWM
Retain cashflow-adjusted high-water mark and recurring **25% cumulative Profit Lock**. Deposit and withdrawal are never trading profit. Preserve the existing approved withdrawal-reserve-first and one-month deposit-rebase behavior. The exact arithmetic for multiple cashflows, skipped milestones, and cycle boundaries still requires independently reviewed numerical cases; refuse ambiguous automatic migration/rebase. Do not release legacy reserve balances.

### D2 — Drawdown (already decided; do not replace)
The Owner confirmed the risk discussion was settled previously. **Canonical reference:** `docs/architecture/RISK_PROFILE_V2.md` and `config/risk_governor_v2.json`.
- NORMAL <10%; CAUTION 10–<23%; RECOVERY_FACTOR_ONLY 23–<35%; 35%+ Katarina-caused or unknown: same-day EMERGENCY_LOCKDOWN.
- Verified manual-origin 35%+ may be evaluated for EXTREME_SURVIVAL / EXTREME_RECOVERY only under independently verified account-wide broker facts and Risk Governor approval. Unknown origin never grants permission.
- 5% hard per-entry risk ceiling, 8% total open risk ceiling inclusive of manual/pending exposure. Existing adaptive and soft caps may be stricter. No forced lot escalation.
- Broker-session clock, floating/realized attribution, cashflow-adjusted HWM, and emergency-lock priority require genuine broker evidence; do not infer live readiness from offline tests.

### D3 — Smart Exit
HOLD/FULL/PARTIAL/TRAIL based on strong independently verifiable reversal evidence **after spread, commission, slippage and execution costs**; weak, stale, contradictory or unreconciled evidence cannot force predictive early exit. Owner manual positions remain untouched without specific authorization. Exact confidence thresholds, partial proportions and observation horizon require research validation, not invented fixed values.

### D4 — Gradual evidence-based growth
Increase risk gradually only after prospective/out-of-sample evidence, execution-cost and risk checks, tested canary/rollback, and an independent Risk Governor veto. Never blindly compound size or use martingale; quantitative step thresholds remain gated by validation.

### D5 — Neuro-Link / Fast-Deep
Single shared cognitive brain. **Fast** for routine checks; **Deep** for complex decisions and conflicts. Preserve provenance, deduplication, knowledge quarantine and source weighting. Deep is not required on every tick. Timing/budget/confidence routing needs measured offline tests.

### D6 — Cloud Hands loss of connection
Per-account **Local Survival Guardian** preserves protective local safety behavior when disconnected; **NO NEW ENTRY** until authenticated connectivity, state reconciliation and fresh risk clearance have been independently verified. No stale queued replay. Never alter Owner manual positions without authority. TLS/WSS/auth, staged signed updates, incident logging and recovery testing remain release blockers.

## Engineering acceptance and no-trade guard
1. GitHub `main` remains canonical; work via reviewed branch/PR. No VPS file cleanup or deployment from this record.
2. Add deterministic unit/integration tests for cashflow/HWM edge cases, DD origin and broker-day fencing, cost-aware exit, evidence-gated growth, Fast/Deep routing and disconnect/reconnect NO_NEW_ENTRY.
3. Run full GitHub Body CI and record receipts; MT5-specific proof stays on isolated VPS/demo tester.
4. Track each gap as PASS/BLOCKED and never equate documentation or synthetic success with complete implementation.
5. **Live execution OFF**; no order or change to active trading until explicitly authorized by Owner after evidence review.

Owner decisions referenced: user instruction of 14 October 2026; existing `KATARINA_OWNER_DESIGN_BASELINE_20261014.md` and `RISK_PROFILE_V2.md`.
