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
