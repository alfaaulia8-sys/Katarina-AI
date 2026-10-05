# KATARINA AI — Stage 10 Database & Memory V1 Boundaries

Status: DRAFT / Stage 10 Step 1  
Scope: durable event and memory boundaries only

## Purpose

Stage 10 adds persistence without weakening the frozen safety and transport
contracts from Stages 04–09. Persistence is infrastructure. It never grants
risk approval, arms execution, creates discretionary BUY/SELL decisions, or
bypasses broker reconciliation.

## Four persistence lanes

| Lane | Storage semantic | Recovery authority | Rebuildable | Live execution authority |
|---|---|---:|---:|---:|
| Event Journal | immutable append-only durable facts | yes | no | no |
| Operational Snapshot | replaceable derived state | no | yes | no |
| Experience Memory | immutable append-only learned/trade episodes | no | yes | no |
| Transient Stream | in-memory / droppable telemetry | no | yes | no |

## 1. Event Journal

The Event Journal is the durable source of operational history.

Persist here:

- decisions and decision evidence;
- risk state changes and risk decisions;
- execution/order/position lifecycle facts;
- account facts required for reconciliation;
- health/safety state transitions;
- reconciliation outcomes;
- any event with CRITICAL or RISK_STATE priority.

Rules:

- append-only;
- immutable once committed;
- deterministic record ID required;
- idempotent duplicate writes required in Step 2;
- restart recovery may trust journal facts only after integrity validation;
- deletion/update-in-place is forbidden in V1.

## 2. Operational Snapshot

Operational Snapshot stores restart acceleration state derived from durable
journal facts and current broker reconciliation.

Examples:

- latest validated runtime state;
- last processed journal cursor;
- last known health/readiness projection;
- cached reconciliation projection.

Rules:

- replaceable;
- rebuildable;
- never the sole source of truth;
- cannot override the journal or broker state;
- must be discarded if schema/integrity/reconciliation checks fail.

## 3. Experience Memory

Experience Memory stores learned or trade-experience observations for later
intelligence stages.

Examples:

- completed trade episode summaries;
- decision context + outcome summaries;
- validated regime/feature snapshots linked to outcomes;
- model evaluation observations.

Rules:

- append-only in V1;
- deterministic record ID required;
- rebuildable from authoritative durable facts where possible;
- advisory only;
- never directly arms execution;
- never directly changes Risk Governor limits;
- never overrides health/readiness/reconciliation state.

Operational state and Experience Memory remain physically and logically
separate. Step 3 will implement that separation.

## 4. Transient Stream

Transient Stream contains high-volume observations that are not durable by
default.

Examples:

- market.tick;
- market.bar;
- transport metrics;
- heartbeats;
- advisory/unknown noncritical runtime events.

A later component may promote selected information by emitting an explicit
durable decision/risk/execution evidence event. Raw transient telemetry is not
silently promoted by the persistence layer.

## Classification precedence

1. CRITICAL or RISK_STATE priority -> Event Journal.
2. Experience-memory topic -> Experience Memory.
3. Snapshot topic -> Operational Snapshot.
4. Durable operational topic -> Event Journal.
5. Known high-frequency telemetry -> Transient Stream.
6. Unknown noncritical event -> Transient Stream.

Priority precedence is intentional and fail-closed: an unknown safety-critical
event must never be lost because of an unrecognized topic name.

## Frozen invariants preserved

- Stage 04 KAT1 remains authoritative for wire framing/schema.
- Stage 06 MT5 bridge remains fail-closed.
- Stage 07 localhost transport/recovery/sequence invariants remain frozen.
- Stage 08 owns data validation and does not arm execution.
- Stage 09 owns health classification and does not approve risk.
- Python remains central intelligence.
- MT5 remains sensor + deterministic safety + execution/reporting layer.
- NO TRADE remains a valid decision.
- Risk Governor remains absolute.
- live-risk readiness remains separate from persistence readiness.

## Step 1 acceptance criteria

Step 1 is complete when:

1. the four storage lanes are explicitly defined;
2. recovery authority exists only in the Event Journal lane;
3. no persistence lane can grant live execution authority;
4. safety-critical priority is always routed durable;
5. transient market/transport telemetry is non-durable by default;
6. unit tests lock these boundary rules before storage implementation begins.

Step 2 may then implement append-only durable records and deterministic IDs.
