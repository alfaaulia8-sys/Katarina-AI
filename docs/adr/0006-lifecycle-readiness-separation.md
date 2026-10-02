# ADR-0006 — Separate Lifecycle From Live-Execution Readiness

**Status:** Accepted  
**Stage:** 05

## Decision

Katarina process lifecycle and permission to open new live risk are separate state dimensions.

`RUNNING` means the Core is operational and processing events.

It does **not** mean trading is authorized.

New live risk additionally requires validated bootstrap state, fresh data, healthy system state, Risk Governor readiness, and explicit execution arming.

## Why

A trading system must be able to remain alive to reconcile, monitor, protect, and recover while refusing new exposure.

## Consequence

Loss of a readiness signal can close new-risk admission without killing the process.

Live execution arming is reset on boot and fault.

Stage 05 audit completed. Lifecycle and live-execution readiness remain separate frozen Core dimensions.
