# Independent final-window audit

The journal validator now reserves the last 20% (at least 12 observations)
before candidate selection. It purges development labels unavailable at the
final cutoff. The existing trainer splits that development history again into
training and selection windows. Neither final features nor outcomes reach model
training or selection. The frozen model is never refitted on the final window.

The fixed 0.55 probability threshold and training-range veto produce diagnostic
filtered net P&L, profit factor and BUY/SELL summaries. A research pass requires
both classes in the final window, Brier improvement of at least 0.005, at least
12 selected observations and positive selected net P&L. This is a screening gate,
not proof of statistical significance, robustness, execution quality or readiness.
The CLI exit status now follows this audit instead of the legacy single split.

September evidence: 136 reconciled observations, net -46.52. Development contains
109 observations (88 training and 21 selection); 27 are reserved for final audit.
Selection Brier is 0.209938 versus baseline 0.204675 (lower is better). The model
is rejected before final model scoring. No candidate is exported or deployed.
The baseline final-window net is -2.21. Source hash and full results are in
`2026-10-10-independent-ai-audit.json`.

This historical dataset has already been inspected. The new partition prevents
programmatic leakage but cannot turn it into a prospective unseen experiment.
Future evidence needs additional market periods with frozen policy, explicit
cost/provenance verification, a fresh MT5 backtest of the filter (position
availability can change), then forward demo observation. Do not tune thresholds
against this final window or present synthetic test results as trading results.
