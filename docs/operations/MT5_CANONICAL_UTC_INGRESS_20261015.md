# MT5 canonical event clock — incoming data conversion

The **market event clock** is the verified MT5 `copy_ticks_range.time_msc` epoch converted to timezone-aware UTC. Every incoming event must be normalized to that same UTC timeline **before** comparison with the market event. UTC is a fixed global standard; the broker may display a different server-local clock.

## Persisted in existing observer output

The existing single observer stores `time_reference` in its atomic `latest.json` along with `market_snapshot_tick_utc` and per-symbol `market_timestamp_utc`. It records the timestamp source, current multi-symbol observed broker-server offset in minutes, confirmation count/confidence, observation time and `historical_dst_verified=false`. A per-symbol `broker_wall_time_display_only` is derived for human presentation. No second observer, new scheduled service, or account identifier is created.

Use `capture_time_reference(infer_clock_shift(...), now_utc)` for the **current** session and `normalize_incoming_time(value,source=...,reference=...)` to convert data:

- `MT5_TICK_TIME_MSC_UTC`: epoch milliseconds from verified historical MT5 tick history. **Only this source is authoritative for market decisions**.
- `EXPLICIT_OFFSET`: ISO-8601 with explicit `Z` or `+/-HH:MM` (including UTC+7 user-supplied data), or timezone-aware `datetime`. Converts to the same UTC timeline, but is not broker market evidence.
- `BROKER_WALL_CURRENT`: a broker-server-local time with **no embedded offset**. Requires current verified multi-symbol reference and explicit receipt timestamp, at most 180 seconds after observation; the converted result must be past-only and no older than 180 seconds. **Not authoritative for decisions**; it cannot be used to infer archived/DST-adjusted broker times.

Unlabeled timestamps, naive external datetime, unsupported timestamp sources, expired offset observations, unverified broker clock, future timestamps, and historical broker-local timestamps are rejected. Do not assume a permanent UTC+3 or apply the current shift retrospectively across DST boundaries. Do not infer a fractional offset from the seconds-level future lead in `symbol_info_tick.time`.

Example: when the current broker display offset is UTC+3, a data item `2026-10-15T13:00:00+07:00` normalizes to `2026-10-15T06:00:00Z`, corresponding to broker display `09:00`. All Brain, candle-cutoff, session and news comparisons continue to use the MT5 market UTC event clock, not the user's time zone or VPS wall clock. VPS time remains a freshness/safety bound and scheduler timestamp.

This change provides a **read-only timestamp conversion contract**, not live execution authority or proof of strategy profitability.
