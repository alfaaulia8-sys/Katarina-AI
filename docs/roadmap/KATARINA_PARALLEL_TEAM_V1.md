# Katarina V1 — parallel research build team (13–19 Oct 2026)

## Team / reporting

**MANAGER** owns the locked week target and the release gate. The Manager
consumes an independently verified QA receipt, not individual unsupported
claims. QA verifies every specialist report, code regressions, common Git
commit and SHA-256 evidence receipts. Four specialist roles start **at the
same time** on independent GitHub-hosted workers:

| Role | Real execution | Output |
|---|---|---|
| Ideas | Bounded genetic exploration of new strategy rule combinations | Candidate JSON shortlist, hypotheses, count |
| Coding | Compile and audit/fingerprint core AI/strategy/governance modules | Module integrity hashes, change proposal |
| Mathematics | Replay BUY/SELL mathematics with spread and fee penalties | Eight cost stress comparisons, risk warning |
| Logic | Detect future-bar lookahead and verify unchanged production risk | Causal/holdout safety findings, next tests |
| QA (after specialists) | Verify 4 receipts, same commit; run full unit+static+integration regressions | QA PASS/BLOCKED; tampered files fail |
| Manager (after QA) | Merge role receipts, decide priority and release gate | Final PASS/BLOCKED by commit and source evidence |

Manual runner: `.github/workflows/katarina-parallel-team.yml`.
All automatic push/PR CI restrictions remain unchanged. The four roles are
**real separate jobs**, not four names in a single model prompt.

Each specialist produces `build/team/roles/<role>.json` with Git commit,
source checks, recommendation and source-payload SHA-256 digest. QA checks
all four and recomputes their digests. Manager recomputes the specialist
receipts and validates the QA handoff. This is integrity, **not a digital
signature** or defense against a fully compromised runner.

## Operational boundaries

1. Agents **do not** push commits, open orders, change code, deploy VPS,
   access MT5 credentials, or grant broker risk permissions.
2. Specialist execution is currently **deterministic engineering
   automation**, not six separately connected external LLM brains. The
   optional multi-model research adapters are a separate component and
   their real external end-to-end connection remains unverified.
3. Ideas use clearly **fabricated OHLC**. Math conclusions are examples,
   not actual alpha or broker evidence. No fabricated approvals.
4. QA can PASS the engineering team yet Manager still reports V1 release
   BLOCKED until the seven-day checklist gates are met (real external
   model response, verified real market data, independent forward evidence).
5. GitHub Actions artifacts expire after seven days. No recurring task,
   background VPS daemon or automatic release is created.

## Manager priority and deadline

D1 audit and role receipts → D2 real external AI proof → D3 validated
external price data → D4 chronological data-based discovery →
D5 sandbox improvement proposals → D6 integration/regressions →
D7 V1 research release candidate decision (19 Oct 2026).

A PASS is evidence for **engineering readiness**, not verified profitability.
Every failing role or QA gate blocks release. Never call a release ready
without the real-market evidence and CI artifacts.
