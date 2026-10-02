# KAT1 — HEDGING / NETTING EXECUTION CONTRACT

**Status:** FROZEN CANDIDATE  
**Version:** 1.0.0  
**Stage:** 04/40

## Scope

Katarina V1 supports both MT5 hedging and netting account modes.

The account mode is a broker/account fact and must be carried explicitly in HELLO_ACK and account state.

## Hedging Mode

Properties:

- multiple positions may exist for one symbol;
- a position is addressed by broker position ticket plus stable position identifier;
- close/reduce intents target one explicit position;
- opposite positions do not imply automatic netting.

Katarina still tracks POSITION_IDENTIFIER because server-side ticket changes and history/reconciliation require stable lineage.

## Netting Mode

Properties:

- only one net position exists per symbol;
- same-direction fills increase the current net position;
- opposite fills may reduce, close, or reverse it;
- POSITION_IDENTIFIER is the stable lineage key;
- POSITION_TICKET may change on reversal.

Therefore Katarina does not use POSITION_TICKET alone as identity.

## Revision Guard

Every position snapshot/delta carries a monotonically advancing Katarina-side `position_revision`.

Every execution intent approved against an existing netting position carries:

- approved_position_revision;
- expected_position_effect;
- expected_net_side;
- expected_net_volume_after_units;
- netting_guard policy.

If the live state no longer matches the approved revision/effect assumption, the gateway must not blindly execute the stale intent.

## Pending LIMIT / STOP on Netting Accounts

A pending order can later change an existing net position even if account state changed after placement.

Therefore pending Katarina orders are lineage-bound and guarded.

Required behavior:

1. capture current position revision at approval;
2. store expected resulting net effect;
3. keep the pending order under lifecycle observation;
4. if relevant position state changes materially before trigger, mark the pending intent stale;
5. cancel it when policy requires;
6. if cancellation outcome is ambiguous, block affected new risk and reconcile.

## MARKET / LIMIT / STOP V1 Scope

Supported:

- BUY / SELL MARKET;
- BUY / SELL LIMIT;
- BUY / SELL STOP.

Reserved, not V1 production-authorized:

- BUY STOP LIMIT;
- SELL STOP LIMIT;
- CLOSE_BY as a Katarina entry mechanism.

Broker capability negotiation may further restrict the supported set.

## Broker-Native SL

Any Katarina-owned order capable of creating exposure must include the approved native Stop Loss.

This applies to MARKET, LIMIT and STOP entries.

If current broker rules do not permit the approved Stop Loss to be represented safely, the entry is rejected.

## Shared Account

Manual/foreign account activity is visible to the Risk Governor and learning pipeline.

It does not automatically grant Katarina mutation authority over those positions/orders.

Manual activity can also change netting account state. Such changes invalidate stale Katarina pending assumptions just like any other material position change.

## Reconciliation Identity

Preferred lineage relation:

~~~text
POSITION_IDENTIFIER
  ↕
ORDER_POSITION_ID
  ↕
DEAL_POSITION_ID
~~~

POSITION_TICKET is preserved as a current broker handle but not treated as an immutable identity in netting mode.
