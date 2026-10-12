# V9 broker-candle entry diagnosis — read-only research

- Historical MT5 M5 BID OHLC **and each candle's recorded spread points** from demo broker on Windows VPS, June 1–Aug 31 2026 (bar timestamp in UTC).
- Script: `scripts/research/broker_entry_diagnostics_v9.py`. It can run from Python in-memory on VPS; it never calls any order, account, or file-write function. MT5 must report `terminal.trade_allowed=false`, otherwise fail closed.
- Compare *the exact four V8 signal families* against two **predeclared** new entry variants, `TREND_EXPANSION_V9` and `SWEEP_2C_CONFIRM_V9`, each BUY and SELL separately.
- Strict closed M5/H1 features and next-M5-bar entry. BUY fills at modeled ASK = recorded BID open + bar spread; SELL exits reference ASK = BID bar price + recorded spread. These are **spread-based approximations, not historical actual ASK candles or verified tick executions**.
- Adverse one broker tick at entry and exit; stop-first on ambiguous candles and adverse gap through stop; 0.03R assumed fee and extra +0.10R scenario. Broker commission, swap, true fill slippage and trade history remain unverified.
- Outputs **aggregated counts, mean R, PF, months and median historical spread / ATR**. No price data, customer/account identifiers, broker dumps, or credentials may be written into the public GitHub repository. VPS used exclusively to read and compute evidence, no persistent result files.
- Main research is retrospectively **previously inspected**, not independent OOS. It cannot authorize live trading regardless of simulated metrics.
- The older June–August V8 public dataset was M5 reference prices with fixed assumed spreads; **do not equate its results with broker-derived spread evidence**.
- Historical dates are not a substitute for forward validation. Production KATARINA remains RESEARCH-ONLY / WAIT.

## Actual VPS broker-read historical M5 test (verified 12 October 2026)

**Source:** demo broker MT5, native `copy_rates_range` for each of the 17 available symbols, UTC requested **2026-06-01 through 2026-08-31**, using recorded M5 BID OHLC and positive historical `spread` points. The read-only Python runner was loaded in **memory from commit `0b300ca`**. No VPS files were created, modified or written, no trading orders, no account data read, and no private bar/tick rows uploaded. Terminal `trade_allowed=false` checked before tests.

**Verification:** GitHub Actions `KATARINA V9 Broker Entry Research Safety` [PASS](https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions/runs/38204858249); `Body CI` [PASS](https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions/runs/38204858245). Broker replay executed separately and completed successfully, in read-only Python on the VPS.

**Headline:** 6,557 overlapping hypothetical event results (4,329 V8 and 2,228 new V9 prototypes). Event-weighted mean base R **-0.150738 R** (0.03R assumed fee already subtracted), after additional 0.10R stress **-0.250738 R**. **0** strategy/symbol/side combinations pass the predeclared all-three-month minimum of 20 trades, PF >=1.20 and mean >=0.10R, even before extra stress. This is **not** an executable portfolio, as mutually incompatible hypothetical events overlap.

### Per instrument

| Broker symbol | Broker M5 bars | Median historical spread (points) | Median spread / M5 ATR | Paper events | Mean R (base) | Mean R (+0.10 R cost) |
|---|---:|---:|---:|---:|---:|---:|
| EURUSD.vx | 18942 | 13 | 0.53699 | 106 | -0.20213 | -0.30213 |
| GBPUSD.vx | 18935 | 17 | 0.51965 | 105 | -0.06706 | -0.16706 |
| USDJPY.vx | 18940 | 26 | 0.88136 | 60 | -0.35579 | -0.45579 |
| USDCHF.vx | 18943 | 14 | 0.60494 | 87 | -0.03827 | -0.13827 |
| USDCAD.vx | 18940 | 19 | 0.76218 | 31 | -0.52325 | -0.62325 |
| AUDUSD.vx | 18942 | 14 | 0.61635 | 36 | -0.12227 | -0.22227 |
| NZDUSD.vx | 18940 | 19 | 0.90169 | 5 | -0.04357 | -0.14357 |
| EURGBP.vx | 18942 | 19 | 1.57396 | 0 | — | — |
| EURJPY.vx | 18943 | 29 | 0.75605 | 45 | -0.13683 | -0.23683 |
| GBPJPY.vx | 18941 | 29 | 0.56546 | 90 | -0.15705 | -0.25705 |
| AUDJPY.vx | 18943 | 29 | 0.84937 | 19 | -0.09067 | -0.19067 |
| EURAUD.vx | 18943 | 22 | 0.58223 | 29 | -0.2053 | -0.3053 |
| XAUUSD.vx | 18058 | 29 | 0.06442 | 1910 | -0.12405 | -0.22405 |
| BTCUSD.vx | 26411 | 2976 | 0.35025 | 743 | -0.15076 | -0.25076 |
| XTIUSD.vx | 18054 | 15 | 0.81395 | 3 | -1.04205 | -1.14206 |
| US30.vx | 18120 | 35 | 0.14294 | 1525 | -0.15612 | -0.25612 |
| NAS100.vx | 18121 | 34 | 0.13309 | 1763 | -0.16806 | -0.26806 |

### Entry method comparison across markets (descriptive, overlapping hypothetical results)

| Proposed method | Event count | Mean R (base) | Mean R (+0.10 R cost) |
|---|---:|---:|---:|
| BREAKOUT_RETEST | 189 | -0.155575 | -0.255575 |
| LIQUIDITY_SWEEP_RECLAIM | 1049 | -0.193927 | -0.293927 |
| RANGE_MEAN_REVERSION | 1272 | -0.169873 | -0.269873 |
| SWEEP_2C_CONFIRM_V9 | 1096 | -0.168681 | -0.268681 |
| TREND_EXPANSION_V9 | 1132 | -0.118879 | -0.218879 |
| TREND_PULLBACK | 1819 | -0.120964 | -0.220964 |

### Credible explanations of losses and constraints

1. **Broker friction invalidates very-short-term FX entries.** EURUSD median broker spread / M5 ATR is 0.53699, GBPUSD 0.51965, EURGBP 1.57396, and Oil XTIUSD 0.81395. The V8 baseline veto (>0.20) correctly rejects many expensive M5 opportunities; removing that veto indiscriminately would not improve price costs. Explore longer horizons (M15/H1) using a **separately declared** stop/cost model instead of loosening a filter after seeing these P/L results.
2. **Fixed assumed public spreads were not representative of broker prices.** For example, XTIUSD historical median spread was 15 points at 0.01 point (= 0.15 in price), whereas public-sample USOIL research used a fixed assumed 0.05. This is a comparison of different data sources and not proof of historical execution costs.
3. **Two limited XAUUSD SELL research leads** survived just +0.10 R additional hypothetical cost: SWEEP_2C_CONFIRM_V9/SELL (117 events, 0.008305 R mean); TREND_EXPANSION_V9/SELL (112 events, 0.017058 R mean). They fail the all-three-month rule. In particular, expansion SELL was negative in July, and sweep SELL had low July mean R. These are **not** promoted or claimed to be profitable.
4. **No reproducible broker edge:** no group passed the month-by-month criterion. Merely increasing leverage, layering, RR, or position size cannot make these negative expectancy rules robust.

### Model limitations and research protection

- Market prices: historical broker **BID OHLC and per-bar `spread`**, with ASK approximated as BID + bar spread. Not true synchronized tick-level historical BID/ASK.
- Entry is next M5 opening bar; stops prioritize worst-case when SL and TP both fall within the same M5 bar. Volatility/market-regime signals use exclusively *closed* M5/H1. Paper fill uses one broker trade tick of adverse entry and exit slippage.
- **Assumed fee 0.03R** plus +0.10R stress. No verified historical account commission, swap, market-depth/liquidity, actual fill, contract minimum sizing, or swap/margin P/L. Median broker tick values are snapshot metadata, not transaction evidence.
- Research dates have been previously inspected: **not independent OOS**; six prototype families and BUY/SELL differ in signal density, thus do not compare aggregate event sums as portfolio P/L or a statistical confidence interval. Do not run live.
- **Next research priority:** redesign FX cost-to-volatility entry horizon (M15/H1), apply actual broker execution restrictions, and independently recheck XAUUSD SELL candidates on later/unseen time periods without repeatedly fitting the same tape.
- Full machine-readable **aggregated, price-free and account-free** evidence is available at `docs/research/outputs/20261012/broker_entry_v9_aggregate_sanitized.json`. It contains model strategy-by-side monthly metrics, *not* broker trade logs, raw candles or tick datasets.
