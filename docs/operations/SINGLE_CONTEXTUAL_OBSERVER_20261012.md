# KATARINA single-pipeline contextual observer — 2026-10-12

## The ONLY new observer lane

`scripts/ai/run_contextual_market_observer.py` is one **one-shot** broker
reader that calls the EXISTING core components:

1. `resolve_broker_symbols` identifies at most 17 real broker symbols.
2. `run_decision_brain_v3.bars_for` reads the same closed M5/M15/H1
   candles, with current broker-clock consensus from
   `broker_clock_alignment`. Do not start another scanner.
3. `public_context.ContextStore` caches official Fed, ECB, BoE RSS
   plus this-week economic calendar with 15-minute fetch backoff.
   Articles are followed from those feeds to the **OFFICIAL PUBLISHER
   HTML** and the complete paragraph body, not RSS title text.
   Unverifiable source, redirects, incomplete content, stale or
   future timestamps and contradictory policy language cannot
   produce an actionable inferred policy direction. Body and SHA-256
   remain on private VPS in SQLite, NEVER pushed to GitHub.
4. `verified_policy_context` identifies unambiguous explicit rate
   announcements in the full body and outlines an explicitly
   CONDITIONAL rate/asset transmission mechanism; ambiguous or
   unrelated articles are unknown, not silently positive/negative.
   It uses no vendor LLM and cannot be described as trained alpha.
5. `MarketDecisionBrain.evaluate_contextually` synthesizes actual
   multi-timeframe conditions, verified attributed articles, economic
   blackout, spreads, risk telemetry gate and existing forward
   evidence gate. **Real account DD/exposure and independently
   verified forward fills are NOT connected**, so `system_healthy=False`
   and `resolved_experience=[]`; no executable trade can result.
6. `ContextDecisionJournal` remembers a candidate or WAIT once per
   symbol/closed M5 bar. A later actual quote may resolve a
   **15-minute bid/ask quote markout**, NOT filled broker trade, R,
   cost-adjusted return, learned strategy or promotion evidence.
   Expired/missing quotes are explicitly marked missing.

Single file output:
`C:\KatarinaDev\artifacts\contextual-observer\latest.json`,
plus `context.sqlite3` and one `worker.lock` in the same directory.
Single writer lock, only one Windows Scheduled Task, no GitHub
dispatch or commit traffic, and no production/web dashboard rewiring.
One pass prints only aggregated counts.

## Non-overlap and safety

- Preserve existing `run_market_brain.py`, `run_readonly_decisions.py`
  and `run_decision_brain_v3.py` for compatibility, but do **NOT**
  simultaneously enable their legacy Windows observer tasks.
- Reuse existing task `Katarina-MarketBrain-Observer` when scheduling
  the new one-shot canonical runner, with `IgnoreNew` concurrency.
  `Katarina-DecisionObserver-ReadOnly` and
  `Katarina-AnalogMemory-Observer` remain DISABLED.
- Do not modify execution adapters, live EA, Risk Governor, account
  trades, broker terminal flags or trader risk settings.
- Tick-clock offset is inferred **for current read-only observations
  only**, not retroactively applied to 2025–2026 research data.
- Real-time feed not available? WAIT with reason. Only full article
  body can generate a policy inference; never convert headlines alone
  into purported AI analysis.
- No new GitHub workflow is created. Existing single Body CI is the
  automated validation path after source changes, so cleaning previous
  CI fanout is preserved.

## Explicit limitations

- The policy inference is deterministic, deliberately conservative,
  not an LLM understanding complete regulatory nuance; complex full
  articles become **UNCERTAIN** pending robust independent source.
- Market regime observation does not imply profitable strategy.
- Forward quote markouts are only diagnostic; independent verified
  bid/ask + commissions + broker fills remain missing.
- No live trading and no changes to production.

## One additional secondary full-article news source (same observer, no duplicate cron)

The canonical observer also uses
`src/katarina/intelligence/market_article_context.py` to query **one
existing CNBC World RSS**, throttled to one RSS fetch every 30 minutes
and one article body fetch per observer pass. Full text is cached in
the **same private context.sqlite3** and never written to GitHub.
Cached articles require real publisher paragraphs, a SHA256 body digest,
a dated feed item within 24 hours and the verified CNBC HTTPS origin.

Its report includes `media_articles_analyzed_from_body` with a short
fact-focused excerpt drawn **from the actual article paragraphs**,
a conditional asset-transmission mechanism, explicit
`bias_harga_terverifikasi=UNCERTAIN`, the non-primary-source caveat,
and the article provenance and read-time. These descriptive media
summaries can help KATARINA understand market events but **never**
become `MacroEvidence.source_verified` or a permission to open a
position. Only the official Fed/ECB/BoE full articles are candidates
for explicit monetary policy context, and those too remain conditional.

No additional observer, cron, GitHub Action, credentials or broker
order path is introduced.
