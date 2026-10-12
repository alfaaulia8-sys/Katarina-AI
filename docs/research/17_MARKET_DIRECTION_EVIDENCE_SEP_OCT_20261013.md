# KATARINA AI — 17-instrument native directional evidence audit

Verification date: 2026-10-13 Jakarta time. Research only, zero submitted broker orders.

## What was actually built and verified

- **One Brain only.** `MarketDecisionBrain` V3 now exposes independent BUY/SELL momentum evidence and opposition on closed M5/M15/H1. `directional_consensus.py` categorizes three-timeframe agreement, mixed evidence, range edge, pullback, reversal or strong higher-timeframe contradiction. A strong H1+M15 contradiction in an existing trend/pullback context can only turn a technical signal into WAIT. It never creates a new BUY/SELL and does not override the Risk Governor.
- The preexisting `ContextualDecisionIntelligence` now carries `directional_alignment`, `directional_observations`, and H1/M15 ATR-normalized momentum, including counterevidence, into each observer's JSON card. It continues to forbid paper/live execution without verified forward trade costs, risk telemetry and macro evidence.
- **Actual broker M5 spread snapshots.** `causal_market_replay.py` can now use MT5 historical M5 closed-bar `spread` multiplied by that symbol's `point`. The signal sees only the prior closed-bar spread, never a future spread. A candidate with missing spread is excluded rather than assigned an invented 0.04x ATR figure. This gives more realistic *observed historical spread at signal time*, but the ask at the NEXT bar's actual entry is still modeled.
- **Research VPS controls.** `run_native_brain_causal_broker_replay.py` now supports all 17 broker-discovered symbols in groups of 3–5, caps each batch, and supports a historical UTC cutoff window without giving the Brain future candles. No new observer, cron, automatic live order gateway or GitHub fanout was added.
- **Scientific review.** `aggregate_directional_brain_replay.py` enforces disjoint symbol batches and valid provenance. `compare_directional_replay_periods.py` compares two nonoverlapping retrospective windows for BUY and SELL, but cannot mislabel them as pristine out-of-sample tests or merge unrelated batch equity curves.

## Actual broker replay — 17 instruments

Broker universe: EURUSD, GBPUSD, USDJPY, USDCHF, USDCAD, AUDUSD, NZDUSD, EURGBP, EURJPY, GBPJPY, AUDJPY, EURAUD, XAUUSD, BTCUSD, XTIUSD, US30 and NAS100 (broker suffix `.vx`).

| Metric | September 2026 partial window | October 2026 partial window | Total |
|---|---:|---:|---:|
| Native Brain closed-bar decision instants | 17,669 | 18,970 | **36,639** |
| Historical hypothetical OHLC-proxy trade labels | 908 | 1,065 | **1,973** |
| Adaptive research virtual selections, per independent batch | 0 | 3 | **3** |
| Broker orders sent | 0 | 0 | **0** |

The 3 October selected modeled trades totaled about **-1.284R** after the fixed extra 0.15R assumption. **All eight method/side groups were negative** on both retrospectively inspected windows after 0.15R modeled additional transaction costs: RANGE_FADE BUY/SELL, TREND_PULLBACK BUY/SELL, BREAKOUT_RETEST BUY/SELL and REVERSAL_RECLAIM BUY/SELL. This is evidence AGAINST immediately trusting existing setup rules in their present form, not proof that future markets cannot be profitable.

Limitations: price evolution is M5 BID OHLC with conservative stop-first logic, not true intrabar tick execution on every case; the assumed next-open ask is the entry BID plus the previously observed *signal-bar* spread. Actual market slippage, full trade commission, swaps, DST transition handling and fill order remain **unverified**. The same already-inspected historical prices are not independent prospective evidence. Closed-bar range M5 data is from the MT5 terminal and can be limited by its history cache.

Detailed raw report files are PRIVATE on the VPS in `C:\KatarinaDev\artifacts\contextual-observer\`: `directional-broker-spread-batch1..4.json`, `directional-september-batch1..4.json`, `directional-brain-17markets-summary.json`, `directional-brain-17markets-september-summary.json`, and `directional-brain-sep-oct-independent-window-comparison.json`. The last filename denotes distinct sampled historical windows, NOT independent unseen validation.

## Observer and deployment proof

- Native read-only observer smoke: **17/17 symbols**, **0 sensor failures**, **17 WAIT**, **0 broker orders** on 2026-10-12T18:21:03Z; 6 cards with full three-timeframe agreement, 6 mixed and 5 unassessed due to missing conditional side.
- One existing `Katarina-MarketBrain-Observer` task runs on the VPS every five minutes; it was briefly paused during bounded market replay and restored. Both redundant legacy observer tasks remain disabled.
- New directional display is available in the SAME contextual card output (no separate Brain or duplicate dashboard feed).
- VPS RAM remained tight after historical research (about 138 MB available on a sample). Two MT5 terminals, interactive user Chrome and Remote Desktop Commander were deliberately **not** killed. All heavy tests remain sequential bounded research, not permanent resident workers.
- CI proof for latest code SHA `d621ea685512a7a4072426776a5aacd9c17a8773`: [KATARINA Body CI PASS run 38290257969](https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions/runs/38290257969). VPS targeted unit tests also passed.

## Source-grounded constraints

- Official MetaQuotes [copy_rates_from_pos](https://www.mql5.com/en/docs/python_metatrader5/mt5copyratesfrompos_py) documents that MT5 returns historical bar timestamp, OHLC, tick_volume and **spread**; it is available only to the extent of terminal chart history.
- Official MetaQuotes [copy_ticks_range](https://www.mql5.com/en/docs/python_metatrader5/mt5copyticksrange_py) documents UTC-epoch broker tick history for later BID/ASK fill-model auditing.
- Arian et al., [Backtest overfitting in the machine learning era](https://doi.org/10.1016/j.knosys.2024.112477) (2024) emphasizes leakage, regime shifts and repeated-optimization risk. Thus no favorable retrospective subgroup is automatically promoted.

## Operational conclusion

**Engineering and safety improvements are deployed, historical robustness is NOT achieved.** The next useful research is to propose genuinely different, precommitted side-specific entry/exit models (and get real tick-entry costs) then test against untouched historical dates and new independent forward observations; do not simply tune 8 losing groups on the same two windows. Final execution status remains **WAIT / NO LIVE**.
