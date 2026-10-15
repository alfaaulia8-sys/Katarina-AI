# Katarina AI — Owner Master Design implementation traceability (14 October 2026)

**Canonical Owner decisions:** https://docs.google.com/document/d/1jR80gSoN2mYlAzwoy373vKJmkvcBtTc4H-alaQtNL0Q/edit

**This is an implementation audit, NOT new architecture approval or a declaration of live readiness.**
New explicit Owner decisions override archived/draft notes. Never infer deployed
readiness from a file's mere existence. All current checks are offline, read-only
for broker data and do not submit orders.

## How to verify

From repository root with the same Python dependencies as standard offline CI:

```powershell
$env:PYTHONPATH="src;."
python -B scripts/ai/verify_master_design_traceability.py
python -B -m unittest discover -s tests/integration -p test_master_design_traceability.py -q
```

The machine-readable inventory is `config/master_design_traceability_v1.json`.
`verify_master_design_traceability.py` validates all **18 areas, exactly six
unresolved decisions, 28 distinct file-level SHA-256 evidence references**, and
runs the canonical 10-module offline unified acceptance. The file count may
change when reviewed evidence paths are added; it is not a completion score.

## Reviewed implementation ledger

| Approved Master Design area | Current verified scope | Remaining work |
|---|---|---|
| A01 Single brain | Offline verified | Broker/production proof not part of current acceptance |
| A02 Growth subject to capital protection | Offline guards verified | Trading growth evidence missing |
| A03 Independent research, asymmetric BUY/SELL | Partial | Wider validated research and broker outcomes |
| A04 Full integrated cognition | Partial | Fast/Deep and calibrated predictive model |
| A05 Selective lifelong memory | Partial | Dedup, quarantined provenance, retention and consolidation |
| A06 Scientific alpha, OOS, canary | Partial | Real independent forward/cost evidence; approved thresholds |
| A07 Independent risk and manual exposure | Offline verified | Broker and multi-account end-to-end |
| A08 Cashflow/DD/recovery/lockdown | Partial | Exact attribution, broker day and priority cases |
| A09 Cumulative Profit Lock 25% | Offline milestones verified | Cashflow/rebase edge cases |
| A10 Adaptive entry and pending lifecycle | Partial | Broker execution/TTL/cancellation/reconciliation validation |
| A11 Intelligent per-account/portfolio exit | Partial | Predictive cost-aware portfolio validation |
| A12 Adaptive growth/survival | Partial | Approved quantitative alpha and risk steps |
| A13 Cloud brain with many hands | Not integrated | Verified auth, transports, local survival, SLOs |
| A14 Individual human learning/clustering | Partial | Privacy-isolated behavioral learning and clustering |
| A15 Owner dashboard and authenticated controls | Not integrated | End-to-end verified auth, emergency controls |
| A16 Early-exit counterfactual feedback | Partial | Immutable source-linked predictive horizon and cost proof |
| A17 Neuro-Link & evidence dedup | Partial | Cross-source evidence weighting and scheduling semantics |
| A18 Management & 11 specialists | REMOVED | Removed with scripts, workplan and workflow hooks by Owner on 15 October 2026 |

Offline-verified means the particular existing behavior has tests and acceptance
receipts. It does **not** certify the entire area as production-complete.

## Six open Owner design decisions

D1: deposit/WD/HWM and one-month milestone rebase; D2: DD daily/total,
attribution, broker timezone, hard-stop; D3: predictive exit and counterfactual
cost/horizon; D4: growth evidence, drift, canary, risk steps; D5: Neuro-Link
dedup/evidence/fast-deep internals; D6: cloud/hands performance, security,
privacy/retention and offline incidents.

The approved **25% cumulative Profit Lock**, Risk Governor veto, same-day
Katarina-caused emergency lockdown, and Management removal decision are
not among the unresolved choices and must not be changed opportunistically.

## Work sequencing, no queue buildup

1. Work only from a clean canonical `main` in a new isolated VPS worktree;
   leave the historical dirty Owner `github-main` files untouched.
2. Implement one reviewed design gap at a time; run focused and full offline
   tests. Keep MetaTrader/MetaTester stopped and the observer scheduler off.
3. Open **at most one** active PR, check CI and squash merge only when green;
   verify VPS and GitHub main SHA, and rerun targeted post-merge tests.
4. Keep unresolved design choices and missing broker evidence visible. Never
   mark `master_design_fully_implemented` or `live_trading_authorized` true
   from a static inventory or synthetic tests.

## Release acceptance still blocked

All 18 approved areas are **registered and traceable**, but not all implemented.
Prior 7 matured virtual observations / 6 research cohorts cannot substantiate
real profit, forward expectancy, broker cost, fill accuracy or multi-account
survival. A separate controlled broker-demo/forward, Owner authentication and
explicit Owner approval is required before any live release.
