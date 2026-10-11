# KATARINA GitHub-only replay testing

The **KATARINA Strategy Replay (GitHub)** workflow runs on **GitHub-hosted Ubuntu**, not on your Windows VPS. In GitHub **Actions**, open that workflow and select **Run workflow** to repeat tests. It also runs whenever the replay script, fixture, tests, or this workflow changes on main.

It runs real code paths for trending, range, volatile breakout, RSI reversal and liquidity sweep with 3 timeframes, 3 candle confirmation options, 2 stop ATR options, 2 RR choices and 2 time exits, with chronological train / validation / diagnostic partitions. Its committed CSV is **synthetic and deterministic**: a functionality/regression test, **not evidence of live trading profitability**.

Outputs: Actions > selected run > **Artifacts > katarina-replay-...** > strategy-replay.json. A run can succeed technically even when every tested setup fails the strategy robustness gate. live_execution_authorized=false is mandatory.

## Private broker-chart retest on VPS (no raw broker dataset committed)

Use the same source in a Python 3 environment; standard library only:

`python scripts/research/github_replay.py --input C:\KatarinaPrivateData\ohlc_m15.csv --output build\replay\broker-local.json --min-trades 5`

Input must have headers symbol,time,open,high,low,close,spread,point,volume. time is UTC UNIX seconds; spread is in points, not price units; OHLC are bid bars. Keep licensed broker CSV private, and upload only audit summaries if redistribution rights are unclear. Never include credentials, account data or customer identifiers. For a deep VPS MT5 backtest, first restore/re-download local broker tick data; the GitHub-hosted workflow cannot reach MT5 on the VPS.

The current process does not automatically install or authorize a self-hosted runner. The pre-existing Katarina VPS Lab workflow still needs a properly registered, explicitly authorized Windows runner for MT5-native tests. Do not expose that runner to arbitrary fork PR code.

Validity limits: synthetic prices are fabricated and do not imply alpha; previously viewed broker history is not a fresh independent holdout. OHLC backtest uses stop-first ambiguity and modeled spread/cost, not actual fills, swap/margin or true tick paths. Real trading remains disabled.