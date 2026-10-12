# KATARINA — Audit Entry Gagal + Entry/Exit Brain V2 (12 Oktober 2026)

**RISET / READ-ONLY. Tidak ada promosi LIVE, tidak ada order, dan tidak ada klaim edge yang terbukti.**

## Ringkasan

Sumber: arsip broker MT5 M5/M15/H1 di VPS, tiga instrumen XAUUSD.vx, EURUSD.vx, US30.vx. Sinyal dari snapshot historis **sampling 1 dari 36 candle M5** pada backtest 55 pair sebelumnya. Ini bukan pemindaian setiap candle dan periode 2025–Oktober 2026 telah dilihat saat penelitian lama, sehingga bukan out-of-sample independen.

Exit struktur hanya membaca candle yang sudah ditutup saat sinyal. Simulasi next M5 bar open, spread historis per-bar sebagai proksi, satu point slippage adverse, +0,03R biaya estimasi, stop-first untuk SL+TP intrabar ambigu, maksimum 36 M5 bar. Strategi lama memakai SL 1,2 ATR M5, TP 1,8R, maksimum 24 M5 bar. Model exit berbeda, jadi perbandingan adalah uji mekanisme, bukan eksperimen terkontrol sempurna.

| Model | Transaksi | Avg R | PF | Win rate |
|---|---:|---:|---:|---:|
| Entry/exit lama | 1.504 | -0,14206 | 0,7888 | 33,31% |
| Filter entry V1, exit lama | 377 | -0,03166 | 0,9499 | 37,40% |
| Filter entry V1 + Exit V2 | 203 | -0,07575 | 0,8815 | 35,47% |

**Kesimpulan:** Filter entry meningkatkan selektivitas, tetapi Exit V2 belum meningkatkan expectancy gabungan. Jangan mengganti exit utama atau menaikkan risiko berdasarkan backtest ini.

## Diagnosis SL sebelumnya

| Pair | SL model lama | SL dalam 3 M5 pertama | Recovery +1R setelah SL | Melanjutkan adverse -2R setelah SL |
|---|---:|---:|---:|---:|
| XAUUSD.vx | 394 | 199 | 120 | 211 |
| EURUSD.vx | 211 | 104 | 57 | 116 |
| US30.vx | 368 | 188 | 132 | 175 |
| TOTAL | 973 | 491 (50,5% SL) | 309 | 502 |

Diagnosis recovery memakai 24 bar *setelah SL*, berhenti pada tercapainya +1R recovery atau -2R adverse. Ini informasi retrospektif, **bukan** input sinyal. Banyak yang SL terlalu cepat, tetapi banyak pula yang terus gagal setelah SL. Memperlebar SL untuk semua pair tidak terjustifikasi.

## Per pair setelah Exit V2

| Pair | Trade | Avg R | PF | Win rate |
|---|---:|---:|---:|---:|
| XAUUSD.vx | 112 | -0,22203 | 0,6766 | 30,36% |
| EURUSD.vx | 15 | -0,28153 | 0,6126 | 26,67% |
| US30.vx | 76 | +0,18042 | 1,3264 | 44,74% |

US30 hanyalah *hipotesis*:
- 2025: 28 trade, -0,04843R, PF 0,9163.
- Jan–Mei 2026: 23 trade, +0,39870R, PF 1,8076.
- Juni–Oktober 2026: 25 trade, +0,23592R, PF 1,4081.
- Tambahan biaya 0,10R per trade menurunkan PF sekitar 1,13; biaya 0,20R menurunkannya sekitar 0,97. Tarif stres belum diverifikasi dari eksekusi broker.

US30 belum lolos validasi OOS independen dan tidak boleh dipromosikan live.

## Perubahan kode

- src/katarina/intelligence/structure_exit_plan.py: StructuralExitPlanner causal menghitung stop di luar swing/area M5-M15, memilih target terdekat dari support/resistance M15/H1 dan menolak trade bila RR 1,25–3,5 tidak tercapai. Hanya research.
- scripts/research/audit_entry_exit_v2_3pairs.py: replay baseline 3 pair, audit SL dini / recovery, bandingkan V1 dan Exit V2, biaya dan periode.
- tests/unit/intelligence/test_structure_exit_plan.py: pengujian no-future-candle, validitas OHLC/parameter, no-live.
- src/katarina/intelligence/market_decision_pipeline.py: menambahkan experimental_exit_plan hanya ketika entry research valid dan instrument_point dari broker tersedia. Tidak mengubah Risk Governor.
- scripts/ai/run_readonly_decisions.py: memublikasikan experimental_exit_plan di JSON observasi, tanpa order.

## Hasil riset di VPS

C:\KatarinaDev\decision-backtest-20261012\entry_exit_v2_diagnostic_3_pairs\FINAL_3_PAIR_AUDIT.json

Tiga arsip *_diagnostic.json memuat hasil per pair; per_pair.csv memuat ringkasannya.

## Keterbatasan

1. Broker trade_allowed=False ketika pengujian dan tidak ada pemanggilan API order_send.
2. Tidak ada kalender berita historis terverifikasi. Simulasi mengasumsikan news clear untuk diagnosis teknis saja; entry live tetap WAIT bila news belum jelas.
3. UTC/DST broker server historis belum direkonsiliasi. Semua timeframe dalam terminal yang sama.
4. Bar spread bukan tick nyata. Fill, komisi, slippage, swap, margin dan portofolio/korelasi belum tervalidasi.
5. Backtest menguji satu snapshot tiap 36 bar M5 dan hanya tiga pair dari riset yang telah berulang kali dilihat. Tidak ada data independen.
6. R seluruh trade bukan return modal. Tidak ada equity/growth model akun dengan exposure antarpair.
7. Exit V2 tidak diaktifkan sebagai kebijakan produksi.

## Keputusan riset

- **Jangan terapkan Exit V2 universal:** hasil gabungan masih negatif, rapuh terhadap biaya.
- **US30** kandidat observasi paper dan forward validation dengan frozen rules, bukan kandidat order live.
- **XAUUSD/EURUSD** tetap harus memperbaiki kualitas setup; satu filter entry tidak cukup.
- Bekukan parameter sebelum diuji dengan data setelah 12 Oktober 2026 atau data broker lain yang sungguh belum pernah digunakan.