# KATARINA AI — DEPENDENCY RULES

**Status:** FROZEN  
**Version:** 1.0.0

## Allowed Direction

```text
domain
  ↑
contracts
  ↑
ports
  ↑
engines
  ↑
core
  ↑
entrypoints
```

Adapters sit outside the core and implement ports:

```text
domain/contracts/ports ← adapters
```

Intelligence uses domain/contracts/ports and is orchestrated by core/engines. It may not bypass Risk Governor or execution contracts.

## Dependency Matrix

- `domain` → standard library / narrowly approved pure libraries only.
- `contracts` → domain.
- `ports` → domain + contracts.
- `engines` → domain + contracts + ports.
- `intelligence` → domain + contracts + ports; engine integration only through explicit contracts.
- `core` → domain + contracts + ports + engines + intelligence interfaces.
- `adapters` → ports + contracts + domain + external libraries.
- `entrypoints` → core + adapters + configuration.

## Explicitly Forbidden

```text
domain       → adapters        ❌
domain       → MT5             ❌
risk engine  → ZeroMQ          ❌
decision     → SQLite directly ❌
intelligence → OrderSend       ❌
learning     → broker mutation ❌
contracts    → infrastructure  ❌
```

## Cross-Boundary Communication

Cross-boundary state moves through explicit immutable contracts.

A component must not reach into another component's mutable internals as a shortcut.

## Infrastructure Ownership

External concerns belong in adapters:

- MT5;
- sockets / ZeroMQ / TCP;
- file-system transport;
- databases;
- economic APIs;
- model artifact stores.

## Test Enforcement

Stage 33 CI will enforce dependency rules automatically.

Before that stage, all new modules must be reviewed against this document.
