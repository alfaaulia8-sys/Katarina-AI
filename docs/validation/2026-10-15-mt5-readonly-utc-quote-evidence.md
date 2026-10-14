# MT5 read-only UTC quote evidence — 15 October 2026

**Scope:** one-shot broker connection and read-only quote/contract observation on
the existing Windows VPS terminal. This does not validate execution,
profitability, broker fills, fees, historical DST, or live readiness.

## Immutable source and private evidence

- GitHub source commit tested: ba69c063e4e7efacd39dd1217562b936c3cd9d99.
- scripts/mt5/audit_readonly_quotes.py SHA256 on VPS:
  111DE2B43BAD8EB0C204154D22C2BE7F6DE89DB864F451021701C48CA074A94F.
- Full JSON output retained **privately** on VPS under
  C:\KatarinaDev\artifacts\mt5-readonly-proof\; no account identities,
  credentials, or quote files are committed to this public repository.
- Observed at 2026-10-14T21:23:22.481Z (15 October, 04:23 WIB).

## Clock crosscheck and single-snapshot findings

1. Raw symbol_info_tick().time_msc appeared in the future relative to VPS UTC,
   resulting in **7/7 WAIT**, as required by fail-closed policy.
2. Existing research-only infer_clock_shift obtained a **current +3-hour
   displacement** from a 3/3 EURUSD/GBPUSD/USDJPY quote quorum. This is **not**
   historical DST verification and must not be used to arbitrarily offset
   signal/candle timestamps.
3. The existing canonical last_past_quote queries real past-only
   copy_ticks_range Bid/Ask with UTC bounds. The revised one-shot audit
   observed valid historical-UTC-priced quotes and contract geometry on **7/7**
   selected markets: XAUUSD.vx, EURUSD.vx, GBPUSD.vx, USDJPY.vx,
   NAS100.vx, US30.vx and JPN225.vx.
4. The observed quote ages across the seven symbols were **0.519–1.278 seconds**,
   within the 180-second bounded lookback. These observations are **not**
   historical trade fills or independent forward-performance evidence.
5. The connected account was **demo / USD**. This proves neither real-account
   certification nor cent-account compatibility. No order_send, symbol_select,
   Risk Governor mutation, or account control action was used.
6. Script exit was 0, result PASS_SINGLE_READ_ONLY_OBSERVATION, and flags
   broker_mutation=false, live_execution_enabled=false,
   live_risk_ready=false, strategy_validated=false.

## Release decision

Stage 36 is **still open**. More is required: verified commission/swap and
broker order/deal IDs, real-vs-cent account classifications, reconnect recovery,
paper lifecycle over independent future periods, actual fills, and explicitly
governed Stage 38 owner authorization. A passing single quote snapshot
must never be interpreted as permission to trade.

References: Stage 36 release issue #24 and shadow evidence issue #31.
