# Katarina research foundation — broker risk and public-feed provenance

## Scope and safety
Owner requested foundation completion BEFORE strategy iteration. This set does not alter strategies, method selectors, lot sizing, entry or exit logic, risk exposure thresholds, live execution or MT5 orders. The existing read-only scheduled observer remains the sole market+Brain+Memory process.

## Engineering additions
1. broker_history_coverage.py: one bounded seven-day MT5 history_deals_get read. Captures numbers of trade entries/exits and nonzero commission/swap/fee samples, and a diagnostic net realized ratio versus *current* balance. No ticket IDs, account IDs, absolute balances or money values published. Deposits/cash movements excluded. Missing history cannot be turned into zero risk.
2. official_cache_provenance.py: checks all four existing stored sources (Fed, ECB, BoE and economic calendar). A CACHED fetch status alone is not accepted. Cache receipts must have recent publication of FETCH, valid UTC time, good raw digest, source payload shape and calendar coverage. Failed fetches invalidate previous success until a valid fresh receipt arrives.
3. Canonical observer now includes both read-only probes in the existing report. foundation_readiness.py checks these sources independently and explicitly retains all existing live-trading and model-promotion vetoes.
4. Unit tests cover missing history, malformed deal money fields, nontrade deposits, historical cost-data limitations, cache poisoning, CACHED errors, stale/future receipts and source coverage.

## Non-negotiable limitations
- Historical deals may belong to old EAs and might not cover any new strategy; the account may have changed. They are descriptive evidence only.
- The current seven-day deal sampling window is not a verified complete broker account lifetime risk ledger.
- A current balance denominator is NOT a reliable account day-start equity, portfolio historical peak or complete realized daily loss metric.
- Broker server timestamp historic UTC/DST uncertainty remains, even though the live market tick UTC event clock is observed.
- A verified Fed/ECB/BoE RSS or calendar cache is not a verified macro transmission direction or evidence for a trade.
- Independent AI/model provider reviews, verified actual strategy costs, independent post-freeze outcomes and explicit owner live consent cannot be manufactured.
- Production risk budget remains zero and Algo Trading must remain OFF.

## Definition of done for this stage
Research engineering checks can pass independently of production/trading clearance. A foundation PASS means software sensors, historical provenance, memory and read-only controls operate; it does NOT mean that strategies are profitable or live eligible. Historical quote outcomes remain virtual experience, not real trade execution evidence.

## Verification
Run all intelligence, integration and engine tests; replay one isolated canonical observer on a consistent SQLite backup; then validate the production scheduled observer and the read-only database integrity audit. Verify any Github CI before merging and sync the canonical VPS checkout without starting duplicate observers.
