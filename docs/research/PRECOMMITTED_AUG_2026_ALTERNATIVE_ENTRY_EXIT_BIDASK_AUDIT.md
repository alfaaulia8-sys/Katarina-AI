# KATARINA AI — Precommitted August 2026 Alternative Entry/Exit Audit

**Tanggal laporan:** 13 Oktober 2026 (Asia/Jakarta). **Keputusan: WAIT / NO LIVE.**

## 1. Apa yang benar-benar dikerjakan

Tiga rancangan entry/exit baru dibekukan di commit `5bc2502d6c28c2b45a17cd3517b5823318beaf4c` **sebelum** hasil uji periode Agustus diakses oleh kode rancangan. Perluasan audit ke seluruh tick dilakukan pada commit `fe64934d081429e6a760af79a5ca7f3f47e5c5e3` tanpa mengubah aturan sinyal. Sumber kode:

- `src/katarina/intelligence/precommitted_setup_research.py` — aturan murni, tidak dapat mengeksekusi transaksi; menggunakan candle M5/M15/H1 tertutup dari MT5 dan spread M5 broker pada waktu keputusan.
- `scripts/research/run_precommitted_aug_setup_research.py` — riset broker sekali jalan, pemeriksaan izin terminal trading nonaktif, data diambil melalui jalur MT5 yang sudah ada, pengujian tick BID/ASK baru dilakukan sesudah hipotesis dibekukan.
- `scripts/research/aggregate_precommitted_aug_research.py` — menggabungkan empat batch tanpa memilih hanya hasil bagus, menghitung seluruh label, kandidat tidak valid, serta ketidaklengkapan data.
- `tests/unit/intelligence/test_precommitted_setup_research.py`, `tests/unit/intelligence/test_aggregate_precommitted_aug_research.py` — uji peran stop, reclaim, retest, timestamp dan larangan promosi live.

**Ini alternatif riset, bukan AI Brain kedua.** `MarketDecisionBrain V3`, observer tunggal, Risk Governor dan trading live **tidak diubah**. Prediksi yang diteliti tidak disalurkan menjadi order atau pengalaman `ResolvedExperience` terverifikasi.

## 2. Tiga aturan yang dibekukan

1. **RANGE_SWEEP_RECLAIM:** candle M5 menyapu level channel 20 candle sebelumnya lalu menutup kembali di dalam range dengan wick penolakan yang jelas; syarat tidak ada pergerakan H1 terlalu impulsif. SL di luar ekstrem sweep plus buffer 0,15 ATR M5; TP di **midpoint range sebelumnya**. Hanya boleh masuk jika RR geometri sinyal setelah spread minimal 1,25 dan spread tidak lebih dari 20% risiko awal.
2. **TREND_PULLBACK_RESUME:** arah H1 harus bergerak setidaknya 1 ATR M15 dan M15 searah; minimal dua candle koreksi kontra-tren; candle M5 terakhir benar-benar melanjutkan harga. SL melampaui swing koreksi dan buffer, TP **level likuiditas struktural H1 terdahulu**. Tidak memakai target ATR yang belum terbukti sebagai support/resistance.
3. **BREAKOUT_RETEST_LEVEL:** candle M5 sebelumnya menembus range dari candle yang lebih lama; candle M5 berikutnya menguji dan bertahan di atas/bawah batas itu. SL melewati wick breakout/retest dengan buffer; TP proyeksi **0,8× lebar range sebelumnya**. Semua model punya horizon virtual maksimal dua jam, risiko dan harga BID/ASK aktual pada label hanya disimulasikan, tidak ada order.

Parameter aturan bersifat *predeclared research hypotheses*, **bukan** optimasi terbukti. Uji tidak mengubah indikator, threshold, SL/TP, atau sampel setelah melihat hasil laba/rugi.

## 3. Data dan cakupan

- 17 instrumen broker MT5 dengan nama bersufiks `.vx`, dijalankan berurutan dalam **empat batch 3–5 simbol** untuk membatasi RAM VPS.
- Target kalender **10–21 Agustus 2026 UTC**. Pengujian hanya memakai candle historis tertutup yang ada di terminal; cakupan nyata per simbol direkam dalam laporan privat dan dapat lebih pendek dari jendela nominal.
- Data historis ini terpisah secara kalender dari sampel September–Oktober yang dipakai mendiagnosis strategi lama. **Tidak boleh disebut untouched forward atau independen sempurna**: periode Agustus merupakan pengujian mundur setelah melihat kelemahan strategi September–Oktober.
- MT5 `time_msc` tick digunakan sebagai referensi waktu pasar; sesi sejarah broker dan pergeseran DST lintas musim belum diverifikasi menyeluruh.
- Setiap kandidat dibekukan sebelum data exit dibaca. Maksimum risiko biaya nominal: spread M5 tertutup ≤20% jarak stop berbasis candle sinyal; namun next-open spread sebenarnya baru diperiksa melalui audit tick.

## 4. Hasil semua kandidat, tanpa pembersihan sampel rugi

| Metrik | Hasil |
|---|---:|
| Evaluasi kalender pasar tertutup yang memenuhi kelengkapan | **47.225** |
| Kandidat teknikal beku sebelum outcome | **161** |
| Label keluar via simulasi OHLC M5 | **157** |
| Outcome OHLC tidak lengkap / geometri entry gagal | **4** |
| Rata-rata seluruh 157 OHLC, ekstra biaya asumsi 0,15R | **−0,308641R** |
| PF OHLC proxy pada biaya 0,15R | **0,594147** |
| Rata-rata OHLC, ekstra biaya asumsi 0,30R | **−0,458641R** |
| PF OHLC pada biaya 0,30R | **0,471781** |
| Positif / negatif OHLC, biaya 0,15R | **45 / 112** |

Rentang harga 2 jam dalam OHLC belum merekam urutan eksekusi tick sebenarnya. Karena itu 161 **seluruhnya** dievaluasi lagi menggunakan tick BID/ASK historis yang disediakan terminal broker, bukan hanya 25 kandidat sampel awal.

## 5. Audit menyeluruh BID/ASK asli (simulasi quote, bukan fill broker)

| Metrik | Hasil |
|---|---:|
| Semua kandidat precommitted diaudit | **161** |
| Jalur raw tick BID/ASK + bar M5 referensi valid dan selesai | **157** |
| Referensi raw M5 tidak tersedia | 1 |
| Tick exit tidak lengkap | 3 |
| Rata-rata 157 quote-path, dengan **tambahan biaya asumsi** 0,15R | **−0,315584R** |
| Profit factor quote-path, biaya 0,15R | **0,593206** |
| Simulated quote SL / TP / TIME | **98 / 31 / 28** |
| Tidak ada order MT5 live | **0** |

Quote path BUY memakai entry ASK dan exit BID; SELL memakai entry BID dan exit ASK. Candle BID entry dan raw tick diperiksa konsistensinya; gap dan ketiadaan quote membatalkan label. **Ini masih simulasi harga quote, bukan real account trade, komisi nyata, slippage aktual atau order fill terverifikasi.**

### 5.1 Pembagian menurut strategi dan arah (menggunakan 157 quote-path yang valid)

| Aturan | Side | N | Mean R asumsi +0,15R | PF asumsi | Positive / Negative | SL / TP / TIME |
|---|---|---:|---:|---:|---:|---|
| RANGE_SWEEP_RECLAIM | BUY | 15 | −0,515 | 0,405 | 4 / 11 | 11 / 3 / 1 |
| RANGE_SWEEP_RECLAIM | SELL | **18** | **+0,410** | **1,712** | 9 / 9 | 8 / 8 / 2 |
| TREND_PULLBACK_RESUME | BUY | 25 | −0,461 | 0,422 | 6 / 19 | 15 / 4 / 6 |
| TREND_PULLBACK_RESUME | SELL | 16 | −0,004 | 0,994 | 4 / 12 | 9 / 4 / 3 |
| BREAKOUT_RETEST_LEVEL | BUY | 41 | **−0,735** | **0,185** | 7 / 34 | 30 / 3 / 8 |
| BREAKOUT_RETEST_LEVEL | SELL | 42 | −0,178 | 0,754 | 15 / 27 | 25 / 9 / 8 |

Kesimpulan penting:

- **BREAKOUT_RETEST BUY gagal paling jelas** pada 41 contoh (30 SL, hanya 3 TP). Menambah pengukuran arah saja belum menyelesaikan timing/target.
- **RANGE_SWEEP_RECLAIM SELL tampak menarik** dengan 18 kasus +0,410R setelah biaya asumsi. Tetapi variasi sangat tinggi: bootstrap sederhana (mengasumsikan sampel IID, asumsi yang TIDAK terbukti) memberi persentil sekitar **−0,335R sampai +1,231R**. Nol ada di dalam rentang tersebut; **tidak boleh dipromosikan**.
- TREND_PULLBACK SELL ≈ breakeven setelah asumsi biaya (−0,004R) dan masih belum termasuk komisi/slippage akun riil.
- XAUUSD punya 62 dari 157 simulasi quote yang lengkap, NAS100 40, US30 29: **131/157 ≈83%** berasal dari 3 simbol itu. Meskipun total data menyebut 17 simbol, hasil keuntungan/kerugian **tidak terdiversifikasi**; enam simbol tidak menghasilkan kandidat pada aturan beku.
- Perubahan input tambahan asumsi dari 0,15R menjadi 0,30R menurunkan seluruh rata-rata sekitar 0,15R per kandidat. Sinyal dengan rentang profit tipis bisa berubah menjadi rugi.

## 6. Prioritas yang benar setelah audit

1. **Jangan mengaktifkan strategi apa pun secara live.** Semua hasil retrospektif, termasuk subkelompok terlihat bagus, tidak memenuhi bukti broker fill dan profit out-of-sample.
2. Untuk iterasi berikutnya, **bekukan aturan yang benar-benar baru** sebelum rentang tanggal validasi yang belum digunakan. Jangan memindahkan nilai ambang STOP/TP hanya berdasarkan 157 hasil ini.
3. Peroleh jadwal **komisi nyata, swap, ukuran kontrak, dan data fill** dari akun atau spesifikasi broker yang sah sebelum menghitung PF net nyata. Tidak ada transaksi riil baru yang dibuat untuk memvalidasi ini.
4. Uji tick di periode lebih panjang dengan pergantian rezim volatilitas dan waktu server/DST, termasuk penolakan data tidak sinkron. Tambahkan penerapan pembatas risiko portofolio, korelasi multi-pair dan monthly net P&L hanya setelah jalur eksekusi simulasi validated.
5. Observer tunggal tetap memonitor 17 simbol tiap 5 menit. Semua eksperimen historis berjalan sebagai proses VPS sementara dan selesai; GitHub CI wajib PASS; jalur trading live tetap terlarang.

## 7. Bukti, referensi, penyimpanan

- GitHub [Body CI PASS untuk perluasan exhaustive audit](https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions/runs/38297032416). Tes unit `23` pilihan pada VPS PASS (aturan + agregasi + broker tick reconciliation + sejarah tanggal).
- Laporan mentah privat pada VPS: `C:\KatarinaDev\artifacts\contextual-observer\precommitted-Aug2026-exhaustive-batch1..4.json` dan `precommitted-Aug2026-17market-exhaustive-ticks.json`.
- Dokumentasi resmi MT5: [copy_rates_from_pos](https://www.mql5.com/en/docs/python_metatrader5/mt5copyratesfrompos_py) (bar dan spread), [copy_ticks_range](https://www.mql5.com/en/docs/python_metatrader5/mt5copyticksrange_py) (bid/ask dan UTC).
- Arian dkk. (2024), [Backtest overfitting in the machine learning era](https://doi.org/10.1016/j.knosys.2024.112477), mengingatkan risiko optimasi berulang dan nonstationary market.

**Verdict: pengembangan dan validasi quote-based bertambah signifikan, tetapi strategi baru belum profitable secara menyeluruh, dan tidak ada promosi paper/live otomatis.**
