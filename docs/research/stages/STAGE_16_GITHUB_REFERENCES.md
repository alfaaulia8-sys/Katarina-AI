# Stage 16 — GitHub Prior-Art Reference

Status: SEARCHED / REVIEW INPUT  
Stage: Risk Governor

## Search intent

`trading risk engine limits governor kill switch`

## Selected reference

https://github.com/nautechsystems/nautilus_trader/blob/009ca1f1d99fde9595059fd4471e54bde1d76bf4/crates/risk/src/engine/config.rs

## KATARINA adaptation rule

- Reference is prior art only; code is not copied blindly.
- Frozen Stage 01-09 invariants remain authoritative.
- Python remains central intelligence.
- Strategy/risk policy is not silently finalized.
- Live risk and live execution authority remain disabled.
- The generated Stage 16 component is an integration body shell.
- Functional trading logic requires its own governed implementation and tests.

## Body-build result

`BODY_FRAMEWORK_COMPLETE`

This status means the stage has a stable integration boundary in the KATARINA
body. It does **not** mean production trading logic or live-risk validation is
finalized.
