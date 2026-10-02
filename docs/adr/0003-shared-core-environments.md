# ADR-0003 — Shared Core Across Environments

**Status:** Accepted

## Decision

Live, tester, shadow, and research orchestration should reuse the same domain contracts and production decision/risk core wherever behavior is intended to match.

## Why

This reduces live/test semantic drift and makes backtest/replay failures more useful.

## Limit

Live broker behavior, latency, transport, persistence, and reconciliation cannot be perfectly simulated. Environment differences must remain explicit rather than hidden.
