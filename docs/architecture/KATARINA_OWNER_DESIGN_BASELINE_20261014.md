# KATARINA AI — Owner Approved Design Baseline, 13–14 October 2026

Status: decision baseline for engineering. NOT a live trading approval.
Authoritative register: https://docs.google.com/document/d/1jR80gSoN2mYlAzwoy373vKJmkvcBtTc4H-alaQtNL0Q/edit

PRECEDENCE: newest explicit Owner decisions override older proposals, historic source-code behavior, and obsolete test expectations. Prior decisions remain archival history, not active rules, when superseded.

## Approved active decisions

1. ONE Unified Self-Evolving Cognitive Brain, never multiple independent trading brains.
2. Growth and compounding are optimization objectives; capital protection, independent Risk Governor, NO TRADE and minimum-safe-lot checks are mandatory constraints.
3. Research freely across market structure, tick/candle/liquidity, fundamental/news and regime; asymmetric BUY/SELL methods allowed.
4. Integrated perception, scientific curiosity, causal reasoning, meta-cognition, fast/deep thinking and predictive internal market model.
5. Selective lifelong memory: episodic, semantic, procedural, decision/error memory, provenance, knowledge quarantine, dedup, replay and rollback.
6. Alpha evolution requires out-of-sample validation, prospective shadow forward, cost-aware evidence, independent risk approval, canary and rollback before live use.
7. Main realized-DD accounting based on CASHFLOW-ADJUSTED BALANCE HWM. Equity, free margin, floating P/L and broker constraints remain immediate risk inputs.
8. DD bands: NORMAL 0–10%, CAUTION 10–23%, RECOVERY+SURVIVAL at 23%+. Attribution verified as Katarina-caused 35%+ forces NO NEW ENTRY/RECOVERY that trading day; next-day recovery is evaluation only, never automatic.
9. Manual positions affect total account safety but must not be modified without specific Owner authority; Extreme Survival caused by manual risk is NOT blanket entry permission.
10. RECURRING PROFIT LOCK: whenever verified REALIZED TRADING GROWTH reaches each new +100% milestone, ADD 25% OF ACTUAL TOTAL BROKER BALANCE at the milestone to the unwithdrawn reserve. It is not 25% of profit; it does not replace older locked funds. No external cashflow may fake a trading milestone.
11. Profit Lock is an accounting reserve until Owner actually withdraws; exclude remaining reserve from intentional trading sizing. Withdrawal consumes reserve first; excess requires immediate milestone reference rebase. Deposit updates risk assessment immediately but reference rebase waits the agreed one-month period; exact edge-case arithmetic is deferred.
12. Entry type adaptively market/limit/stop; pending TTL, broker checks, idempotent order IDs, local risk veto, reconciliation and no stale retries.
13. Intelligent account- and portfolio-adaptive HOLD/FULL CLOSE/PARTIAL/TRAIL; different accounts may EXIT differently for the same shared entry. Early exit followed by evidence-aware counterfactual monitoring.
14. Adaptive growth may adjust trading aggressiveness within proven alpha evidence, available risk budget and Risk Governor veto. No forced martingale or blind lot increases.
15. One brain with many sensor/executor hands; per-account Local Survival Guardian, safe offline NO NEW ENTRY, TLS/WSS, authenticated commands and signed staged updates.
16. Human behavioral learning remains individually separated and privacy-filtered; broker feed clustering is only an entry optimization, not merging user memories.
17. Strong Owner authentication, web monitoring/control, emergency pause and audited rollback. Chat identity is not authorization.
18. Latest organizational override: Katarina Management and its 11 specialists are REMOVED by the explicit Owner override of 15 October 2026. Do not require it for the Katarina AI roadmap or insert specialists into the brain.

## Example and integration obligations

Approved no-cashflow milestone example: balance 10,000 => 20,000 (NEW lock 5,000, cumulative 5,000), then 40,000 (NEW lock 10,000, cumulative 15,000), then 80,000 (NEW lock 20,000, cumulative 35,000). Active balance after these events: 15,000 / 25,000 / 45,000. Repeated broker snapshots or restart must NOT double-lock a milestone.

The current 25% cumulative formula must match capital engine, config, risk sizing, persistence and tests. Legacy 30% snapshots can only be preview-migrated; old locked balances are not silently released. A former config assumption that active capital always equals 75% of total at EVERY milestone is INVALID after cumulative locks.

## Exactly six topics reserved for a future Owner meeting

1. Precise cashflow-adjusted Profit Lock/HWM algorithm for multiple deposits, withdrawals, one-month cycle and skipped milestones.
2. Daily-vs-total DD attribution mathematics, Extreme trigger, trading-day/timezone and hard-stop priority.
3. Numerical predictive exit, partial/trailing cost logic and counterfactual horizon.
4. Numeric growth/alpha evidence standards, drift, canary, risk-step and rollback thresholds.
5. Detailed Neuro-Link confidence/knowledge graph, dedup, memory weighting and fast/deep scheduling.
6. Cloud/MT5/hands performance SLO, security/auth deployment, privacy retention and offline incident operation.

DO NOT invent these six unresolved parameters, and DO NOT re-open already-approved 25% Profit Lock or 11-specialist removal.

## Engineering safety

Never force-pull/reset dirty user worktrees. Do not remove broker history, tick data, memory databases, positions, trading service, pending orders or recovery checkpoints. Check available RAM/disk and active processes, isolate development in separate worktrees, run bounded tests, and delete only clearly disposable isolated test caches. Do not enable MT5 live or scheduler. Preserve branch rollback.

STATUS: APPROVED DESIGN is not equivalent to CODE PRESENT, INTEGRATED, TESTED, or LIVE READY. Audit code differences separately from the decision baseline.
