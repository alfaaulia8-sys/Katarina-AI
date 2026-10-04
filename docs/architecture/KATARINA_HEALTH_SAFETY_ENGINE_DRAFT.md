# Katarina Health & Safety Engine — Draft

**Stage:** 09/40  
**Status:** IMPLEMENTATION ACTIVE  
**Version:** 0.1.0

## Purpose

Stage 09 turns validated runtime evidence into a fail-closed system-health classification.

Health dimensions are frozen from KAT1 HEALTH_EVENT:

- data;
- transport;
- execution;
- reconciliation;
- journal;
- clock;
- snapshot.

States are UNKNOWN / OK / DEGRADED / BLOCKED.

## Inputs

Authoritative dimension state comes from KAT1 `HEALTH_EVENT`.

Derived safety evidence also consumes:

- HEARTBEAT for liveness, critical queue pressure and broker observation freshness;
- SESSION_STATE for connection, session tick freshness, trading permission, ping and clock skew;
- TRANSPORT_METRICS for RTT and recent decode-error pressure;
- Stage-08 DATA_FRESH as a one-way health dependency.

Derived evidence may worsen an explicit state. It never upgrades a BLOCKED/DEGRADED explicit state.

## Readiness authority

Stage 09 may set only `ReadinessSignal.HEALTH`.

HEALTH becomes true only when:

1. every health dimension evaluates OK;
2. health/heartbeat evidence is not stale;
3. Stage-08 data freshness is true;
4. at least two consecutive authoritative HEALTH_EVENT observations report all dimensions OK.

This recovery hysteresis prevents a single transient good packet from immediately restoring readiness.

Even HEALTH=true does not imply live trading. Core still requires independent DATA_FRESH, RISK and EXECUTION_ARMED gates.

## Initial fail-closed policies

- heartbeat stale >5s → transport BLOCKED;
- authoritative health event stale >5s → transport BLOCKED;
- frozen critical queue capacity 2048 → BLOCKED;
- critical queue >=1536 → DEGRADED;
- stale broker observation >5s → data BLOCKED;
- open session without fresh tick → data DEGRADED;
- open session without required trade permission → execution BLOCKED;
- terminal disconnected → transport/execution BLOCKED;
- clock skew >=2s → DEGRADED; >=10s → BLOCKED;
- ping/RTT >=250ms → DEGRADED; >=1s → BLOCKED;
- recent decode-error increase → transport DEGRADED for 10s.

Stage 09 does not own capital risk thresholds, execution arming, strategy decisions, or broker mutation.
