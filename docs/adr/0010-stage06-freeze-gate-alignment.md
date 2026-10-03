# ADR-0010 — Stage 06 Freeze Gate Alignment with Stage 04 Account Compatibility

**Status:** ACCEPTED  
**Date:** 2026-10-03  
**Stage:** 06/40

## Context

Stage 04 froze the STANDARD/CENT compatibility contract before Stage 06 existed.

That frozen contract states:

- safe execution and risk sizing must use broker-native account/symbol facts;
- Katarina does not require a binary STANDARD/CENT guess to operate safely;
- STANDARD_LIKE / CENT_LIKE / UNKNOWN classification is informational;
- broker-by-broker validation of both account classes is required at Stage 36/38 before production compatibility claims are made.

During Stage 06 hardening, two real-account probes were added as a proposed Stage-06 freeze gate. Those probes are useful diagnostics, but making both account classes mandatory for the Stage-06 freeze duplicates the Stage-36/38 broker-validation responsibility and conflicts with the earlier frozen scope.

Stage 06 has no enabled OrderSend / OrderSendAsync path and does not make a broker-production-readiness claim.

## Decision

Stage 06 freeze requires evidence for the Stage-06 bridge scope:

1. strict MetaEditor compile on a freeze-qualified modern Windows host;
2. zero errors and zero warnings for:
   - KatarinaBridgeEA.mq5;
   - KatarinaStage06SelfTest.mq5;
   - KatarinaStage06AccountProbe.mq5;
3. non-empty EX5 artifacts for all three targets;
4. complete source-manifest binding;
5. MQL self-test PASS on a freeze-qualified modern Windows host;
6. all Stage-06 Python/static regressions PASS;
7. fail-closed bridge behavior and absence of enabled broker-order submission remain statically enforced.

The STANDARD_LIKE and CENT_LIKE runtime account probes remain implemented and maintained as read-only evidence tools, but they are not a Stage-06 freeze blocker.

They become mandatory evidence for broker/account production compatibility at Stage 36/38, exactly as required by the frozen Stage-04 contract.

## Evidence Provenance

Windows Server 2012 R2 may be used for exploratory deployment/compatibility diagnostics, but it is not freeze-qualified for Stage 06.

Stage-06 freeze evidence must use a PREFERRED or COMPATIBILITY modern Windows validation host for compiler/runtime self-test proof.

## Consequences

Stage 06 can be frozen without pretending that broker-specific STANDARD/CENT production validation has already occurred.

The project must not claim broker-by-broker production compatibility until the Stage-36/38 account-class validation is completed.

The read-only account probe remains available for early diagnostics and deployment checks.

## Non-goals

This ADR does not:

- enable live broker submission;
- weaken native-SL or fail-closed requirements;
- infer account class from currency codes, broker names, or marketing labels;
- waive Stage-36/38 broker validation;
- change the frozen Stage-04 protocol/account-unit rules.
