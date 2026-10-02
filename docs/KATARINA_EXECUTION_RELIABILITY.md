# KATARINA AI — EXECUTION RELIABILITY POLICY

**Status:** FROZEN  
**Version:** 1.0.0  
**Stage:** 02

## 1. Purpose

Prevent duplicate orders, phantom fills, false rejection assumptions, restart inconsistencies, and execution drift between Katarina and the broker.

## 2. Durable Request Journal

Every broker-mutating request receives a unique client/order identity.

Before the first irreversible broker submission attempt, persist:

- normalized request identity;
- normalized payload hash/equivalent;
- execution intent lineage;
- current state = RESERVED;
- timestamp / boot / stream metadata.

Persistence must survive process/terminal restart.

## 3. Idempotency

- Same request ID + same payload: return/recover the known result.
- Same request ID + different payload: reject as IDEMPOTENCY_CONFLICT.
- Never solve a timeout by generating a new broker mutation automatically.

## 4. Execution Truth

OrderSend acknowledgement is not sufficient to prove final broker state.

Proof hierarchy uses:

1. transaction events;
2. broker order/deal IDs and return details;
3. order/deal history;
4. current positions/orders;
5. reconciliation against journal.

## 5. Unknown State

When exact effect cannot be proved:

```text
UNKNOWN
→ no automatic retry
→ block affected execution scope
→ reconcile
```

## 6. Recovery

Startup/reconnect is RECOVERING until:

- journal readable;
- broker state readable;
- identity/binding valid;
- critical event sequence reconciled;
- unknown reservations resolved or explicitly quarantined;
- complete current snapshot installed.

## 7. Event Durability

Critical execution events must be journaled with ordered sequence/cursor semantics.

Realtime transport is a delivery mechanism, not the sole durable source of execution truth.

## 8. Queue Policy

Never silently drop:

- order lifecycle;
- deal/fill;
- execution rejection/unknown;
- position change needed for reconciliation;
- risk-critical account change.

Tick data may be coalesced to latest state during backlog.

## 9. Security Boundary

Baseline live transport is localhost-only. Remote/public socket exposure requires a separate security review.

## 10. Fail-Closed Principle

Any journal corruption, identity mismatch, unresolved execution ambiguity, critical sequence gap, or inability to obtain a complete broker snapshot results in:

```text
NO NEW LIVE RISK
```
