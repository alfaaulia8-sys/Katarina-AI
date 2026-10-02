# STAGE 04 — OWNER DATA DECISIONS

**Status:** OWNER INPUT PARTIALLY RESOLVED  
**Stage:** 04/40  
**Purpose:** Decisions that materially change what Katarina observes or is allowed to execute.

The protocol can be engineered without asking the Project Owner about byte offsets and integer widths. The following items affect trading behavior or operating scope and therefore require owner approval.

## Decision 1 — Account Custody

### OWNER DECISION: B — SHARED ACCOUNT FOR OBSERVATIONAL LEARNING ✅

The account may contain:

- Katarina-owned trades;
- manual user trades;
- other explicitly observable activity.

Purpose:

- Katarina should learn not only from its own decisions, but also from manual user entries;
- manual trades become first-class observation data;
- Katarina records the market context at entry, lifecycle changes, SL/TP behavior, and final outcome;
- declared user reasoning is stored separately from Katarina-inferred reasoning.

Safety boundary:

- **visibility does not imply mutation authority**;
- Katarina may observe all account activity for risk/learning;
- by default Katarina may mutate only positions/orders that are explicitly Katarina-owned;
- manual trades remain read-only unless a future owner-approved assistance policy grants otherwise.

This design requires explicit trade-origin classification and separate learning labels so manual behavior cannot be mistaken for Katarina policy.

**Decision 1 is resolved: SHARED ACCOUNT.**



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

### OWNER DECISION: A — FULL ACCOUNT VISIBILITY ✅

Katarina observes all positions, pending orders, and relevant broker transactions needed for account-wide exposure, reconciliation, and learning.

This includes manual entries and foreign-magic activity.

Rules:

- all activity contributes to account risk/exposure awareness;
- origin and ownership are classified separately;
- Katarina-owned trades and manual-user trades remain distinct learning populations;
- mutation authority stays restricted to Katarina-owned objects by default.

**Decision 5 is resolved: FULL ACCOUNT VISIBILITY.**



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

## Current Owner Decision State

Resolved:

~~~text
1B  Shared account for observational learning
5A  Full account visibility
~~~

Still pending:

~~~text
2   Account-mode certification
3   New-entry order types
4   Protective stop requirement
6   Deposit / withdrawal / credit ledger
~~~

Manual-trade learning is now an approved architectural requirement. See:

- `docs/architecture/MANUAL_TRADE_LEARNING_CONTRACT_DRAFT.md`

The remaining owner decisions can be answered individually later.
