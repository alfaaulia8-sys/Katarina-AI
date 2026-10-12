# KATARINA Brain V5 — Full M5 Intraday First / Extreme Scalping

**Status: READ-ONLY RESEARCH. No live orders, no trade authorization, no proven profitable strategy.**

Tanggal pembekuan eksperimen: 12 Oktober 2026. Dataset 2025–Oktober 2026 sudah dilihat pada riset sebelumnya; ini *in-sample, not independent out-of-sample*. Jangan memperkirakan return ke depan dari kurva model ini.

## Rancangan yang diperiksa

- Memindai setiap M5 CLOSED bar yang valid untuk **55 pair**, bukan 3 snapshot harian seperti V4.
- Tahap pertama memakai prefilter cepat, berbasis closed H1/M15 trend + actual M5 pullback/displacement. Ini modul hipotesis baru, **bukan** setiap-candle full MarketDecisionPipeline atau model neural terlatih.
- **Intraday (prioritas)**: konfirmasi arah H1/M15, setidaknya dua candle koreksi M5 sebelumnya, displacement >=0,42 ATR, spread <=0,22 ATR. Struktur SL dari extreme lokal + buffer; TP 1,8R; batas waktu 48 M5 (4 jam).
- **Scalp ekstrem (opsi riset)**: sweep+reclaim level 20 candle, rejection wick >=0,45 ATR, tick-volume proxy >=1,25 rerata, spread <=0,12 ATR, H1 mendukung. SL invalidasi candle + buffer, TP 1,3R; maksimal 8 M5 (40 menit).
- Ranking antar-pair dilakukan pada timestamp M5 yang sama tanpa mengetahui return masa depan; jika bersamaan, intraday didahulukan. Pembanding menggunakan pemilihan alfabetis pada kesempatan setara.
- Simulasi satu posisi sekaligus, maksimal dua entry per hari kode waktu broker. Risiko model 0,25% intraday, 0,10% scalp ekstrem, nominal kapasitas harian 0,50%.
- Entry M5 next open, bid/ask diturunkan dari OHLC Bid+spread per bar, stop-first bila SL/TP terjadi di bar sama, slippage dua sisi masing-masing satu point, biaya tambahan intraday 0,03R, scalp 0,06R. Broker round-trip commission tidak tersedia secara historis.

## Data dan hasil portofolio

- Simbol: **55 / 55**; candle M5 yang dipindai: **4,841,611**.
- Hari pengamatan dengan >=20 pair memiliki >=60 bar: **329**.
- Kandidat setup: **39,033** dari **24,562** timestamp berbeda. Kandidat != transaksi.

| Kebijakan | Trades | Days positive / traded | Avg R | Profit factor | Return model | Max DD model |
|---|---:|---:|---:|---:|---:|---:|
| Intraday only | 658 | 187 / 329 | 0.006 | 1.009 | 0.582% | 8.331% |
| Intraday first + extreme scalp | 658 | 181 / 329 | -0.006 | 0.990 | -0.987% | 9.283% |
| Extreme scalp only | 155 | 57 / 126 | -0.168 | 0.702 | -2.583% | 2.854% |
| Alphabetical control | 658 | 167 / 329 | -0.063 | 0.897 | -10.059% | 17.132% |

**No verified sustainable edge:** intraday-only 658 trades, 187 profitable days and 142 loss days, +0,58% *modeled* return, but PF 1,009 and avg only +0,00556R. That is effectively break-even and fragile.
Adding scalp changes selection of earlier daily opportunities (11 scalp entries selected in combined policy) and makes combined performance negative. Pure scalping is decisively negative under tested rules.

## Broker cost stress (intraday only)

| Added cost beyond original model | PF | Avg R | Return model | Max DD |
|---|---:|---:|---:|---:|
| none | 1.009 | 0.006 | 0.582% | 8.331% |
| +0.10R | 0.857 | -0.094 | -14.676% | 18.512% |
| +0.20R | 0.730 | -0.194 | -27.623% | 29.514% |

This stress uses illustrative per-trade R cost increments and is not the precise USD broker bill.

## Historical consistency — intraday

Profitable months: **9 / 16**; negative months **7**.

| Broker-coded month | n | Average R | PF |
|---|---:|---:|---:|
| 2025-07 | 40 | 0.188 | 1.359 |
| 2025-08 | 42 | -0.095 | 0.848 |
| 2025-09 | 44 | -0.083 | 0.868 |
| 2025-10 | 46 | -0.096 | 0.843 |
| 2025-11 | 40 | 0.185 | 1.362 |
| 2025-12 | 44 | -0.147 | 0.765 |
| 2026-01 | 42 | 0.071 | 1.124 |
| 2026-02 | 40 | 0.241 | 1.467 |
| 2026-03 | 44 | -0.337 | 0.540 |
| 2026-04 | 44 | -0.202 | 0.708 |
| 2026-05 | 42 | -0.126 | 0.803 |
| 2026-06 | 44 | 0.027 | 1.044 |
| 2026-07 | 46 | 0.064 | 1.105 |
| 2026-08 | 42 | 0.188 | 1.361 |
| 2026-09 | 44 | 0.040 | 1.066 |
| 2026-10 | 14 | 0.705 | 3.348 |

## Brain agreement — essential integration blocker

- V5 independently preselected **658** trades.
- Previous Explainable Market Brain agreed with direction in **144** of them.
- Only **31** also passed Brain's structural quality and matching true semantic setup.
- This is a post-selection audit, not a revised policy simulation: it does not select the second-best asset when Brain vetoes the top candidate. The numerical V5 return must not be presented as old Brain's return.
- **Action:** keep V5 isolated in research; require consistent Brain/entry quality decisions before any production promotion.

## Broker contract and execution limitations

- Account report currency (not account ID): **USD**.
- Current broker symbol specifications indicate minimum-lot hypothetical affordability in the **same 658 combined-policy entries**: equity 1,000 USD: **292**; 5,000 USD: **600**; 10,000 USD: **642**.
- These are hypothetical capital scenarios, not the actual account capital. Current symbol tick values, minimum lots and stop levels cannot certify historical tradability or margin requirements.
- Spot-check 16 historical tick requests (EURUSD/XAUUSD/US30/JPN225 over four calendar dates): **13/16** returned quote-change ticks near requested time.
- Historical XAUUSD tick data were not available around several 2025–2026 reference dates, despite existing M5 OHLC; this prevents full tick-level execution validation.
- MetaTrader bar spread and per-symbol tick value are broker observations, but the paper fill uses next-bar OHLC, not actual tick sequencing. Commissions, swaps, partial fills, time zones and historical exchange conversion remain unresolved.

## Trading-mode policy

**Primary: INTRADAY RESEARCH ONLY.** Only a preliminary, negligible theoretical edge before full costs; no live permission.

**SCALP_EXTREME: PAPER RESEARCH ONLY, DEFAULT DISABLED.** The tested version worsens expectancy. Use separately only to gather new causal event evidence, not automatically for trading.

**When no verified candidate exists: WAIT.** Intraday profits cannot be guaranteed each day and avoiding a bad trade is an explicit design requirement.

### Work needed before any maturity claim

1. Reconcile the fast full-M5 prefilter and ExplainableMarketDecisionPipeline using identical causal decision inputs. Verify multi-pair portfolio replay with the Brain gate actually in force.
2. Reconstruct historical tick bid/ask fills, spread variation, commission and swap at sufficient sample coverage, plus margin, volume steps, risk sizing and session/time-zone alignment.
3. Freeze one set of rules and perform a truly new forward or independent chronological holdout after freeze; evaluate expected R, PF, max equity drawdown and monthly consistency with costs.
4. Do not deploy live until the external evidence and risk governor explicitly support it. No order_send was called.

Output paths on VPS: C:\KatarinaDev\decision-backtest-20261012\intraday_scalp_full_m5_v5\

Primary research code: src/katarina/intelligence/intraday_scalp_research.py; scripts/research/backtest_full_m5_intraday_scalp_v5.py.

Docs basis: MQL5 Python copy_rates_from_pos, copy_ticks_from, symbol_info. Broker-specific commission, time-zone and instrument behavior require separate verification.