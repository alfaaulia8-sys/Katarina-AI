# Katarina V6 — 15 October 2026 strategy improvement backtest

## Executive gate

**READ-ONLY RESEARCH, NO-GO LIVE.** The new XAUUSD BUY >=0.80 candidate is materially better in the already-inspected historical M5 model, but **not independently proven profitable**. Do not alter live EA, Smart Entry, Risk Governor or observer settings based on these results. The SELL strategy needs different rules or separate validation; do not assume BUY and SELL should use the same playbook.

The V6 backtest runs causal technical scanning, semantic setup checks, entry-quality validation, Brain vetoes, portfolio selection, and **M5 OHLC modeled next-open fills**, not verified historical bid/ask tick fills. Actual historical news remains **counterfactually verified**, so these model runs are not realistic approved trading signals. Already-inspected history cannot become unseen OOS just by running another parameter.

## Control and experimental methodology

- Source: MetaTrader 5 ALFA demo historical CLOSED M5/M15/H1 candles, no broker orders.
- Isolated backtest evidence on Windows VPS: `C:\KatarinaFreshLab\build-proof\isolated-backtest-20261015`, separate from source checkout and scheduled observer.
- Research script: `scripts/research/backtest_unified_intraday_brain_v6.py`.
- New optional flags: `--minimum-signal-score 0.8`, `--research-side BUY|SELL|BOTH`, `--output-dir <isolated path>`. Default score 0.0 and BOTH preserve the existing historical V6 setup.
- **Important:** the score and side gates act on candidate-known information **before** Brain acceptance, future fill outcomes and portfolio ranking. Each alternative re-runs the full portfolio selection, rather than retrospectively deleting losing fills from a CSV.
- All model returns already include V6's preexisting modeled bid/ask spread, adverse point and extra **0.03R cost allowance**. The +0.10R and +0.20R scenarios represent additional *hypothetical* friction; broker fees, commissions, swaps and slip cannot be claimed verified.

## Fresh broker-history backtest — 17 currently selected instruments (25,000 M5 bars each)

Scanned **416,673 closed M5 bars**, 64 market-coverage days, **5,621 raw intraday candidates**.

| Portfolio variant | Final model trades | PF basic | Modeled return basic | Max model DD basic | PF +0.10R | PF +0.20R |
|---|---:|---:|---:|---:|---:|---:|
| V6 unchanged, BUY+SELL | 98 | 1.1517 | +2.1299% | 3.1267% | 0.9816 | 0.8405 |
| Causal score >=0.80, BUY+SELL | 38 | 1.1179 | +0.6526% | 1.3052% | 0.9556 | 0.8206 |

Neither full 17-market variant survives added 0.10R costs. A naive global score floor is **not** a robust strategy upgrade. Do not promote.

## XAUUSD 329-day historical ablation (up to 90,000 requested M5 bars)

Source yielded **88,209 closed M5 bars**, **329 coverage days**; **6,785 raw intraday candidates**. Each row independently reruns the candidate gate and V6 one-position portfolio.

| XAUUSD research variant | Trades | PF basic | Return basic | Max DD basic | PF +0.20R | Return +0.20R |
|---|---:|---:|---:|---:|---:|---:|
| Original XAUUSD BUY+SELL | 227 | 0.9443 | -2.1513% | 8.6133% | 0.6962 | -12.6535% |
| BUY only, candidate score >=0.80 | 40 | **1.5721** | **+2.9919%** | **0.8452%** | **1.1557** | **+0.9535%** |
| SELL only, candidate score >=0.80 | 61 | 0.9089 | -0.8885% | 2.9769% | 0.6585 | -3.8669% |

For XAUUSD alone, the BUY >=0.80 hypothesis deserves separate future testing. It is **not** a proof of deployable alpha, due to small sample, selection on already-inspected data, incomplete real costs and missing tick fills. The SELL hypothesis was loss-making; defer it rather than copy BUY's settings.

### Chronological descriptive check for XAUUSD >=0.80

These periods were already inspected by the broader research program; none are an independent pristine holdout.

| Period | BUY trades | BUY PF basic | BUY PF +0.20R | SELL trades | SELL PF basic | SELL PF +0.20R |
|---|---:|---:|---:|---:|---:|---:|
| Jul–Dec 2025 | 15 | 2.2287 | 1.6194 | 15 | 1.6785 | 1.1941 |
| Jan–May 2026 | 16 | 1.2344 | **0.9075** | 28 | 0.9279 | 0.6737 |
| Jun–Oct 2026 | 9 | 1.3717 | 1.0190 | 18 | 0.5101 | 0.3764 |

The BUY hypothesis **fails** the +0.20R positive-PF condition in Jan–May 2026 and is barely above 1 in Jun–Oct; it needs further validation, not production approval. Last ~92-day XAUUSD-alone check was 9 BUY trades (PF1.3717) versus 16 SELL trades (PF0.4133).

## Enforced boundaries and next go/no-go

**Never** enable live execution from these statistics. Keep one scheduled canonical read-only observer, no duplicate worker, and terminal Algo Trading OFF. Use real new prospective signals after method freeze to test BUY >=0.80, verify entry quotes and exit bid/ask tick chronology, fees/slippage, and compare over independent time. Treat 0 new signals as a signal-generation blocker, not passing evidence. No trading, risk or promotion parameter is changed by this PR.

For reproducibility (from repo root with MetaTrader5 Python installed and terminal Algo Trading OFF):

```powershell
python scripts/research/backtest_unified_intraday_brain_v6.py --symbols XAUUSD.vx --bars 90000 --minimum-signal-score 0.8 --research-side BUY --output-dir C:\KatarinaFreshLab\build-proof\isolated-backtest-20261015\XAU_90000_080_BUY
```

Use separate output directories for baseline, BUY, SELL, 7-market and 17-market variants. Do not modify previously recorded outcomes. This is M5 research, **not native MT5 every-tick Strategy Tester certification**.
