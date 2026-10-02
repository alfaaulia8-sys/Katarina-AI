# Tests

Planned test families:

- unit;
- integration;
- contract;
- protocol/conformance;
- replay;
- property;
- regression;
- later end-to-end and stress tests.

Critical risk/execution invariants should become executable tests as implementation stages progress.


## Stage 05 Core Tests

Current Stage 05 standard-library test suite:

```text
tests/unit/core/test_stage05_core.py
```

Coverage currently includes lifecycle, dependency graph validation, bounded ingress, readiness gating, deterministic dispatch, lifecycle-scoped subscriptions, reverse shutdown, fault cleanup, and live-risk fail-closed behavior.

Development command:

```bash
PYTHONPATH=src python -m unittest discover -s tests -v
```

On Windows Command Prompt:

```bat
set PYTHONPATH=src
python -m unittest discover -s tests -v
```

Full automated CI remains Stage 33.
