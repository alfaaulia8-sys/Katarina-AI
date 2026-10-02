# KAT1 V1 — IDENTITY AND BINDING CONTRACT

**Status:** FROZEN CANDIDATE  
**Version:** 1.0.0

## Account ID

KAT1 never sends the broker login as the primary portable account identity.

Canonical account_id is the first 16 bytes of SHA-256 over:

~~~text
UTF8("KAT1/account-id/v1")
0x00
uint32_le(len(broker_server_utf8))
broker_server_utf8
0x00
ASCII(decimal broker_login)
~~~

Raw broker_server and broker_login are still carried for diagnostics and binding.

## Instrument ID

`instrument_id` is a uint32 mapping established by the active stream's SymbolSpec catalog.

It is only meaningful with:

- account_id;
- stream_id;
- SymbolSpec/spec_revision.

No trading decision may rely on an instrument_id from another account/stream without remapping.

## Stream ID

`stream_id` is a persistent nonzero uint64 generated once for one logical MT5 bridge journal namespace and persisted across normal restarts.

A lost/recreated journal creates a new stream_id and forces bootstrap/reconciliation.

## Boot ID

`boot_id` is a new nonzero uint64 on every successful bridge initialization.

A repeated boot_id in a new boot is invalid.

## Trace IDs

Katarina-generated lineage identifiers are 128-bit opaque values:

- client_instance_id;
- snapshot_id;
- execution_intent_id;
- order_id/client_request_id;
- decision_id;
- risk_decision_id;
- reconciliation request IDs;
- manual annotation IDs/actor IDs.

Generation must provide at least 122 bits of effective randomness or an equivalently collision-resistant scheme.

Wire form is two uint64 little-endian words / 16 opaque bytes. Human logs use 32 lowercase hexadecimal characters.

## Execution Binding

Every execution intent binds to:

- account_id;
- instrument_id;
- spec_revision;
- approved account revision;
- approved position revision when applicable;
- decision/risk lineage;
- risk binding hash;
- submit expiry.

Any binding mismatch is fail-closed.
