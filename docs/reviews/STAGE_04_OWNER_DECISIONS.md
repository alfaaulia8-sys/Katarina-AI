# STAGE 04 — OWNER DATA DECISIONS

**Status:** OWNER INPUT REQUIRED  
**Stage:** 04/40  
**Purpose:** Decisions that materially change what Katarina observes or is allowed to execute.

The protocol can be engineered without asking the Project Owner about byte offsets and integer widths. The following items affect trading behavior or operating scope and therefore require owner approval.

## Decision 1 — Account Custody

### A. Dedicated Katarina account — RECOMMENDED

Only Katarina is expected to trade the live account.

Advantages:

- simplest reconciliation;
- strongest protection against foreign/manual mutations;
- cleaner learning data;
- clearer risk attribution;
- easier recovery after restart.

Disadvantage:

- manual trades or another EA should not share that account.

### B. Shared account

Manual trades and/or other EAs may coexist.

Advantages:

- more operational flexibility.

Disadvantages:

- more complex reconciliation;
- external positions change margin/exposure;
- attribution becomes harder;
- learning data needs origin classification.

**Recommendation: A — Dedicated.**

---

## Decision 2 — MT5 Account Mode Certification

### A. V1 certified for HEDGING first — RECOMMENDED

Schema still carries the account-mode enum so netting can be added later.

Advantages:

- position ticket/identifier model is clearer for the initial XAUUSD specialist;
- partial close and multiple concurrent positions are straightforward;
- smaller first execution surface.

Disadvantage:

- netting accounts are not production-certified initially.

### B. HEDGING + NETTING from V1

Advantages:

- wider broker/account compatibility.

Disadvantages:

- more state-machine and reconciliation cases before first stable release.

**Recommendation: A — Hedging-first certification, schema supports both.**

---

## Decision 3 — New Entry Order Types

### A. MARKET entries only in V1 — RECOMMENDED

KAT1 can reserve enums for future LIMIT/STOP orders, but V1 capability negotiation disables them.

Advantages:

- smaller execution surface;
- simpler idempotency;
- simpler stale-price logic;
- easier validation for scalping.

Disadvantage:

- strategies requiring passive/pending entries must wait for a later capability version.

### B. MARKET + LIMIT + STOP from V1

Advantages:

- more strategy flexibility.

Disadvantages:

- expiration, replace/cancel, partial lifecycle and stale pending-order logic are added immediately.

**Recommendation: A — Market-only entry for V1.**

---

## Decision 4 — Protective Stop Requirement

### A. Broker-native protective SL required for new live positions — RECOMMENDED

A live OPEN is rejected if the approved protective stop cannot be represented/accepted under broker rules.

Advantages:

- exposure remains protected if Python/transport/VPS fails;
- aligns with fail-safe architecture;
- risk is explicit at entry.

Disadvantage:

- a valid model entry may be rejected when broker stop-distance/freeze rules prevent the required SL.

### B. Allow positions without broker SL

Advantage:

- maximum strategy flexibility.

Disadvantages:

- connectivity/process failure can leave naked exposure;
- risk becomes dependent on continuous software availability.

**Recommendation: A — SL mandatory.**

---

## Decision 5 — Visibility of External Positions and Orders

### A. Full account visibility — RECOMMENDED

Katarina observes all open positions and pending orders needed to understand account-wide margin/exposure, including foreign magic/manual activity.

Mutation authority remains limited to Katarina-owned namespace unless a future explicitly governed emergency policy says otherwise.

Advantages:

- correct total risk/margin;
- detects unexpected broker/account activity;
- safer reconciliation.

Disadvantage:

- snapshot size is slightly larger.

### B. Katarina-only visibility

Advantage:

- smaller state.

Disadvantage:

- Risk Governor can be blind to capital already consumed by other activity.

**Recommendation: A — Full account visibility.**

---

## Decision 6 — Deposit / Withdrawal / Credit Ledger

### A. First-class ACCOUNT_LEDGER_EVENT in V1 — RECOMMENDED

Track broker balance operations separately from trading P/L.

Advantages:

- balance changes cannot be mistaken for strategy profit/loss;
- better capital accounting;
- cleaner learning/performance evaluation;
- supports future reserve/withdrawal logic.

Disadvantage:

- requires history synchronization and extra reconciliation logic.

### B. Defer ledger events

Advantage:

- smaller V1.

Disadvantage:

- external cashflow must be inferred later and can distort performance accounting.

**Recommendation: A — Include ledger events.**

---

## Decisions the Owner Does NOT Need to Make Yet

These are engineering/runtime calibration issues and should not block Stage 04:

- exact number of historical bars per timeframe;
- exact active timeframe list;
- queue capacities;
- CRC on every advisory tick;
- latency thresholds;
- ZeroMQ socket options;
- model features;
- indicator periods;
- strategy thresholds;
- DOM/order-book usage;
- news provider choice.

Protocol enums can support future changes without hard-coding strategy configuration into the wire format.

## Recommended Owner Response

To accept all recommendations, reply simply:

~~~text
Pakai semua rekomendasi Stage 04.
~~~

Or override individual items, for example:

~~~text
1A
2A
3B
4A
5A
6A
~~~
