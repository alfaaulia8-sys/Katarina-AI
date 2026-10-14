# Katarina AI — engineering / research evidence, 14 October 2026

Status: **ENGINEERING TESTS PASS, TRADING EDGE NOT VALIDATED, LIVE RELEASE BLOCKED**.

## Engineering evidence

- GitHub Body CI run [38487539223](https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions/runs/38487539223), commit `789e430ad47f18702c26662812bd5543ee10bcbe`: **SUCCESS**. Unit 1,066 / static 101 / integration 24 = 1,191 tests.
- Isolated VPS checkout of that exact commit passed Katarina Management acceptance: pinned and clean, 11 specialists verified, 34 required regressions passed, QA passed, release **BLOCKED**, 0 orders, no autonomous code-writing workers verified and no external AI workers verified.
- Capital restore rejects malformed records before runtime state mutation; old 30% reserve migration is **preview-only**, never silently applied. Risk limits for existing Owner positions remain enforced.
- VPS remote connection worked with MT5 terminals closed; Python MT5 SDK available but neither authenticated MT5 terminal nor account read session was present. No native broker deal P/L or broker-day validation was performed.

## Strategy falsification — do not cherry-pick

An earlier 55-symbol semantic study from the project evidence reported **zero** eligible paper candidates and **zero** validated live strategies. Combined filtered mean: **−0.14473 R** per trade; profit factor: **0.7847**. The previously inspected historical dataset, incomplete broker cost/news verification and sampled-bar replay invalidate any claim of forward alpha.

Additional bounded rule discovery used the existing `run_autonomous_strategy_discovery.py` on 5,000 **closed M15 OHLC bars** for each instrument from the private stored file `mt5_20261012_m15.csv`, with seed 77, population 12, generations 2. Both instruments completed 17 unique rule trials (BUY and SELL are independently selectable), 3 retained diagnostics each; train/validation/holdout split 60/20/20, stop-first for intrabar ambiguity; spread = 0.04 ATR and fee = 0.04 R are **assumptions**, not broker-calibrated costs.

| Instrument | Dataset digest SHA-256 | Best reported diagnostic (validation R) | Same candidate held-out R | Verdict |
| --- | --- | ---: | ---: | --- |
| XAUUSD.vx | `45de6b62495a4df3c0272f934e603d6849e6fe251f97af1abd3ceda5198e4ec0` | +0.088165 (SELL, 85 trades) | −0.030862 (94 trades) | REJECT / NO PROMOTION |
| NAS100.vx | `31a605a737cf8de87377c812450f01800e1ca6165ff816d8b853596e5527b3a1` | +0.235175 (BUY, 59 trades) | −0.041334 (48 trades) | REJECT / NO PROMOTION |

This was a **re-use of previously available research data**, not an unseen prospective forward holdout; neither positive validation slice justifies promotion. The complete machine-readable research and Markdown summaries remain on the Owner VPS under `C:\KatarinaDev\artifacts\katarina-owner-research-20261014\` (no private price CSV was committed to GitHub). The isolated research and Management test worktrees were removed after testing.

## Remaining blocking work

1. Independently authenticated, complete MT5 deal + marked P/L snapshots, per-position provenance and server trading-day evidence, without modifying Owner positions.
2. Risk-controlled **authorized** migration of saved legacy policy state against reconciled broker balances and external cash flows.
3. A genuinely new, prospective, broker-cost-verified positive-edge evaluation of a strategy before paper/demo promotion. Trading methods need not be symmetric for BUY and SELL; do not force equal methods.
4. Repeated demo forward testing, operational monitoring, health/reconciliation enforcement and explicit Owner approval **before any live execution**.
5. Katarina Management currently has deterministic QA/workplan specialists, **not verified external AI coding agents**. The cancelled recurring schedule remains disabled.

**Authorization: WAIT**. MT5/trading live remains disarmed. This research report cannot function as a release receipt or activate any order path.
