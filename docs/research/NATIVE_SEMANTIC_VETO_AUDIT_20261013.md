# KATARINA AI — Verifikasi kelanjutan & gerbang keaslian setup, 13 Oktober 2026

## Ringkasan keputusan

**Perubahan engineering teruji; profitabilitas tetap BELUM terbukti; broker live tetap NO GO.**

Kode sumber `51e7725ab5e2a0da00a6b6b83802da302afbb103` menegakkan pemeriksaan *price-action semantics* yang **sudah ada** pada Brain utama V3. Sebelumnya `MarketDecisionPipeline` menghitung `CausalSetupValidator`, tetapi `MarketDecisionBrain` belum mewajibkan kecocokan pola itu pada `technical_signal`. Sekarang jika nama strategi tidak sesuai bukti candle tertutup, sinyal teknikal dibatalkan menjadi **WAIT**. Tidak dibuat otak strategi, worker, cron, model LLM, atau gateway order tambahan.

## Penguatan sistem yang sudah berjalan

- `MarketDecisionBrain` menggunakan `observation.semantic_setup` native jika sisi strategi sama, atau validator native yang sama jika berbeda. Tidak ada analisis harga masa depan.
- `TREND_PULLBACK` mensyaratkan ada koreksi harga sebelum candle melanjutkan tren; `BREAKOUT_RETEST` mensyaratkan breakout terdahulu dan candle retest; `RANGE_FADE` serta `REVERSAL_RECLAIM` mensyaratkan sweep/rejection yang dapat diperiksa.
- Penolakan adalah **hard veto** saja: tidak dapat menciptakan BUY/SELL, melampaui larangan berita/risk governor, atau mengaktifkan live.
- Hasil `pattern_semantically_confirmed` dan `pattern_semantic_blockers` diteruskan ke struktur `ContextDecision` yang sama agar pengguna dapat memeriksa alasannya.
- Tes memverifikasi bahwa tren sintetis yang tidak benar-benar pullback **tidak boleh BUY walaupun paper risk diizinkan**, hasil validator rusak/gagal bersifat fail closed, dan simulasi pola yang benar tidak menciptakan hak live.
- 54 unit test lokal pada VPS **PASS**; GitHub Body CI [PASS run 38294648480](https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions/runs/38294648480).

## Audit read-only October 2026, 17 broker symbols

Empat batch sekuensial dari kode dengan gerbang semantik, menggunakan data tertutup M5/M15/H1 dan spread historis M5; hasil menjadi arsip privat `semantic-replay-oct-batch1..4.json` dan `semantic-oct17-research-private.json` pada direktori state VPS.

| Ukuran | Hasil |
|---|---:|
| Instrumen broker | 17 |
| Evaluasi pasar memakai Brain utama | 31.139 |
| Kandidat dengan label simulasi OHLC | **158** |
| Jalur kandidat tidak lengkap/censored | 10 |
| Simulasi diterima oleh mesin pengalaman adaptif | 0 |
| Mean R asumsi agregat 158 kandidat, biaya tambahan 0,15R | **−0,278R** |
| Order MT5 nyata | 0 |

Tidak dilakukan penggabungan ekuitas batch terpisah sebagai satu portofolio. Hasil 158 kandidat **bukan** forward demo dan belum memiliki spread BID/ASK entry sebenarnya, slippage, komisi/swap, atau kepastian urutan tick intrabar. Jumlah keputusan yang dievaluasi berbeda dari audit sebelum gerbang sehingga jumlah kandidat sebelumnya **tidak sebanding secara langsung** dan tidak boleh diartikan sebagai pengurangan rugi/profit yang tervalidasi.

| Metode/arah | N | Mean R simulasi setelah +0,15R asumsi |
|---|---:|---:|
| BREAKOUT_RETEST BUY | 7 | +0,074 |
| BREAKOUT_RETEST SELL | 4 | −0,140 |
| RANGE_FADE BUY | 14 | −0,354 |
| RANGE_FADE SELL | 38 | −0,639 |
| REVERSAL_RECLAIM BUY | 3 | +0,457 |
| REVERSAL_RECLAIM SELL | 2 | −1,150 |
| TREND_PULLBACK BUY | 35 | +0,101 |
| TREND_PULLBACK SELL | 55 | −0,312 |

Kelompok tampak positif bersampel 3–35 yang telah dipilih setelah melihat data riset lama **bukan keunggulan yang terbukti**. Ketika simulasi stres biaya tambahan naik ke 0,30R, rata-rata TREND_PULLBACK BUY dan BREAKOUT_RETEST BUY juga berubah menjadi negatif. `RANGE_FADE SELL` masih paling buruk dan membutuhkan pendekatan entry baru yang jelas, bukan sekadar menaikkan bobot indikator.

## Uji operasional pada broker

Setelah GitHub CI dan tes VPS, satu eksekusi langsung observer MT5 menghasilkan **17 instrumen terbaca, 17 WAIT, 0 order**, waktu pasar `MT5_HISTORICAL_TICK_TIME_MSC_UTC`. Satu observer kanonis dipulihkan melalui `finally` setelah empat batch, dan dua observer lama tetap nonaktif. Snapshot uji langsung mencatat satu setup semantik terkonfirmasi; belum memenuhi keseluruhan syarat trading.

## Prioritas riset *precommitted* berikutnya

Ketiga usulan berikut belum diaktifkan sebagai jalur trading dan **harus dibekukan sebelum data evaluasi baru digunakan**:

1. **RANGE_FADE asli:** entry hanya setelah candle M5 menembus batas range terdahulu lalu menutup kembali di dalam batas (*sweep and reclaim*), disertai wick/rejection; stop pada sisi luar titik sweep dengan buffer struktural; target awal midpoint range M15 terdahulu, bukan H1 jauh yang tidak tersedia dalam dua jam. Jika spread melebihi 20% estimasi risiko atau RR bersih gagal, WAIT.
2. **TREND_PULLBACK terkonfirmasi:** H1 dan M15 tidak menentang, minimal dua candle koreksi nyata sebelum M5 resume, stop melewati swing koreksi valid, target prior structural liquidity yang benar; uji BUY dan SELL terpisah.
3. **BREAKOUT_RETEST sesuai namanya:** breakout terbukti pada candle tertutup sebelumnya, retest menguji dan mempertahankan level, stop di balik wick retest yang telah terjadi, target di batas struktur yang tidak memaksa SL setara tiga ATR hanya untuk mengejar H1 jauh.

Evaluasi setiap usulan pada tick BID/ASK independen dan tanggal belum pernah dipakai untuk mendesain aturan, dengan biaya riil, stop-first, 30/60/120 menit predeclared, RR, expectancy, profit factor, drawdown dan tabulasi bulanan. Berita hanya dipakai jika artikel penuh dan timestamp publikasi memang tersedia di saat keputusan. Jangan optimasi ulang berdasarkan September–Oktober yang sudah diperiksa.

## Referensi teknis dan metode

- [MetaQuotes: copy_rates_from_pos — data OHLC dan spread dari chart MT5](https://www.mql5.com/en/docs/python_metatrader5/mt5copyratesfrompos_py).
- [MetaQuotes: copy_ticks_range — timestamp UTC dan tick BID/ASK historis](https://www.mql5.com/en/docs/python_metatrader5/mt5copyticksrange_py).
- [Bailey, Borwein, López de Prado, Zhu — Probability of Backtest Overfitting](https://escholarship.org/uc/item/4w1110bb).
- [López de Prado — Purged and Embargo Cross Validation](https://random-docs.readthedocs.io/en/latest/implementations/cross_validation.html).

**Tidak ada klaim alpha, winrate live, atau promosi otomatis ke risk governor.**
