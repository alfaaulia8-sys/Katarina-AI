# ADR-0001 — Modular Monolith

**Status:** Accepted

## Decision

Katarina starts as one modular Python application process rather than a microservice fleet.

## Why

- lower inter-service latency;
- simpler deployment on one VPS;
- fewer distributed-state failure modes;
- easier debugging and deterministic testing;
- still allows strict internal module boundaries.

## Trade-off

Independent scaling and process isolation are lower than microservices. Ports/adapters preserve an exit path if a future component genuinely needs separation.
