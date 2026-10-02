# ADR-0007 — Capture-Only MT5 Event Handlers

**Status:** Proposed  
**Stage:** 06

## Decision

OnTick and OnTradeTransaction remain capture-oriented and return quickly.

Heavy work, history scans, reconciliation, model computation and blocking transport operations do not run inside those handlers.

## Why

MT5 event delivery is finite and shared with EA processing. Official MQL5 documentation states that the trade-transaction queue has 1024 elements and slow OnTradeTransaction handling can allow earlier events to be superseded.

## Consequence

Trade transactions are copied into a bounded lossless-required local queue. Market ticks may be coalesced to latest state.

This ADR remains Proposed until Stage 06 audit/freeze.
