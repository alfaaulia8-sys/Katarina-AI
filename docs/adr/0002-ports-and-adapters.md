# ADR-0002 — Ports and Adapters

**Status:** Accepted

## Decision

Katarina Core depends on abstract ports. MT5, ZeroMQ, TCP, databases, model stores, and external providers are adapters.

## Why

Infrastructure can change without rewriting decision, risk, memory, or learning logic.

## Consequence

Entrypoints become composition roots and are the main place allowed to select concrete adapters.
