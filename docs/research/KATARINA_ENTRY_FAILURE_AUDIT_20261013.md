# Audit akar kegagalan KATARINA AI — 17 instrumen, September/Oktober 2026

**Status:** audit akar kegagalan selesai; dua bug simulator diperbaiki; batas biaya per risiko diterapkan pada AI Brain; pengujian VPS dan GitHub PASS; produksi live tetap **NO GO**.

## 1. Sumber dan keterbatasan

- 17 simbol MT5 `.vx`, 8 *sequential* batch (masing-masing 3–5 instrumen), dua periode retrospektif yang **sudah pernah diperiksa**, bukan holdout murni.
- Sinyal dibuat oleh **MarketDecisionBrain V3 yang sama dengan observer**, candle M5/M15/H1 tertutup dan spread historis M5 dari MT5 dikonversi ke harga memakai ukuran point broker.
- Harga masuk setelah sinyal menggunakan harga BID *open* candle M5 berikutnya dan **diasumsikan** spread candle sinyal sama dengan spread entry; hasil exit memakai OHLC dan aturan *stop-first*.
- Seluruh R simulasi dikurangi tambahan biaya asumsi **0,15R**. Ini bukan komisi riil, slip, swap, atau fill broker. Harga intrabar tidak diketahui tepat tanpa seluruh tick BID/ASK.
- Fokusnya diagnosis deskriptif semua hasil—**tidak mencari konfigurasi pemenang setelah melihat hasil masa depan**.

## 2. Perbaikan bug yang ditemukan

**BUG A — posisi terkena SL/TP di candle pertama setelah entry sempat terlewati.** Kondisi indeks `end <= signal_index + 1` diganti menjadi `<`, sehingga bar pertama yang valid dapat menghasilkan label stop/target.

**BUG B — posisi tanpa 2 jam harga mendatang sempat ditutup prematur sebagai TIME.** Sekarang, jika target maupun stop tidak tersentuh dan jalur M5 belum mencakup seluruh 24 candle, status dibuat **tidak berlabel / censored**, bukan profit/kerugian rekaan.

Kode: `src/katarina/intelligence/causal_market_replay.py` dengan uji regresi `tests/unit/intelligence/test_closed_bar_failure_forensics.py`. Perubahan baseline akibat perbaikan ini berarti angka penelitian sebelumnya tidak boleh dibandingkan langsung sebagai peningkatan performa.

## 3. Temuan lengkap pasca-perbaikan

| Ukuran | September | Oktober | Gabungan |
|---|---:|---:|---:|
| Keputusan teknikal tertutup dievaluasi | 17.684 | 19.052 | **36.736** |
| Hipotesis teknikal sebelum hasil harga dilihat | — | — | **2.567** |
| Simulasi menghasilkan label harga | **904** | **1.060** | **1.964** |
| Jalur yang tidak dapat dilabeli (sensor/gap/kurang horizon) | 261 | 342 | **603** |
| Stop loss tersentuh | 494 | 604 | **1.098** |
| Take profit tersentuh | 24 | 29 | **53** |
| TIME expiry 2 jam | 386 | 427 | **813** |
| Stop loss pada 15 menit pertama | 223 | 297 | **520** |
| Rata-rata hasil per kandidat dengan extra cost 0,15R | **−0,457R** | **−0,471R** | **−0,464R** |
| Profit factor seluruh kandidat (bukan portofolio terpilih) | 0,360 | 0,364 | **0,362** |

Gabungan 1.513 kalah dan 451 menang setelah biaya asumsi; tingkat kandidat rugi **77,0%**. Stop 55,9% seluruh label, TIME 41,4% dan target hanya 2,7%. Stop sangat cepat 26,5% semua label (47,4% di antara seluruh stop). Dari 813 TIME, **415** masih negatif setelah asumsi biaya.

**Biaya versus potensi:** 1.083 dari 1.964 memiliki *spread saat sinyal* setidaknya 20% dari risiko stop yang disimulasikan pada candle entry berikutnya; 815 setidaknya 30%. Median rasio adalah **0,236R**. Median gerak menguntungkan M5 penuh sebelum label selesai hanya **0,230R**, sedangkan gerak berlawanan **1,026R**. Kedua angka ekstrem M5 tidak memiliki informasi urutan tick dan **bukan** MFE/MAE yang dijamin bisa dieksekusi.

Ambiguitas stop dan TP di **bar M5 yang sama terdeteksi 0** pada sampel tertutup ini, sehingga bukan penjelasan utama kerugian pada periode yang dibatasi. Tidak berarti seluruh order bisa dieksekusi persis seperti label OHLC.

### 3.1 Akar masalah menurut metode dan arah

| Metode | Arah | Kasus | R rata-rata | SL / TIME / TP | Median spread / risiko | Median gerak untung / R |
|---|---|---:|---:|---:|---:|---:|
| RANGE_FADE | BUY | 465 | −0,577 | 317 / 139 / 9 | 30,5% | 0,230 |
| RANGE_FADE | SELL | 703 | **−0,620** | **527 / 172 / 4** | **40,0%** | **0,068** |
| TREND_PULLBACK | BUY | 219 | −0,181 | 54 / 147 / 18 | 12,6% | 0,335 |
| TREND_PULLBACK | SELL | 218 | −0,308 | 90 / 115 / 13 | 13,7% | 0,292 |
| BREAKOUT_RETEST | BUY | 146 | −0,260 | 30 / 115 / 1 | 10,2% | 0,295 |
| BREAKOUT_RETEST | SELL | 160 | −0,225 | 48 / 104 / 8 | 11,1% | 0,315 |
| REVERSAL_RECLAIM | BUY | 34 | −0,698 | 20 / 14 / 0 | 26,3% | 0,000 |
| REVERSAL_RECLAIM | SELL | 19 | −0,169 | 12 / 7 / 0 | 23,8% | 0,642 |

**Kedelapan kombinasi metode + arah negatif pada kedua periode** yang sudah diperiksa. Tidak ada justifikasi menaikkan lot, melonggarkan Risk Governor, atau mengaktifkan live.

**Diagnosa spesifik:** RANGE_FADE SELL memaksakan mean reversion dengan gerak awal berlawanan; 305 dari 703 kasus stop dalam 15 menit pertama, 560 dari 703 mengalami spread ≥20% risiko. RANGE_FADE BUY juga terlalu mahal dan sering langsung tertabrak SL. TREND_PULLBACK dan BREAKOUT_RETEST lebih sering kehabisan horizon 2 jam tanpa TP; median stop BREAKOUT sekitar 3,2–3,5x ATR M15, sementara pergerakan untung hanya ~0,30R. Target/resistance terlalu ambisius relatif dengan durasi uji dan bukti entry belum cukup. REVERSAL_RECLAIM memiliki sampel kecil sehingga tidak bisa dipercaya sebagai alternatif siap produksi.

### 3.2 Seluruh pair, tanpa memilih pemenang

| Pair | N | Mean R asumsi | Median spread / stop risk |
|---|---:|---:|---:|
| EURGBP.vx | 106 | −0,773 | 50,2% |
| NZDUSD.vx | 139 | −0,677 | 37,3% |
| AUDJPY.vx | 124 | −0,673 | 39,0% |
| XTIUSD.vx | 114 | −0,543 | 31,0% |
| AUDUSD.vx | 116 | −0,527 | 29,5% |
| USDCAD.vx | 98 | −0,509 | 29,0% |
| GBPJPY.vx | 124 | −0,498 | 22,4% |
| BTCUSD.vx | 119 | −0,466 | 13,0% |
| USDJPY.vx | 124 | −0,464 | 25,2% |
| EURUSD.vx | 109 | −0,438 | 21,1% |
| NAS100.vx | 100 | −0,430 | 8,5% |
| USDCHF.vx | 118 | −0,430 | 31,1% |
| EURAUD.vx | 101 | −0,399 | 28,0% |
| EURJPY.vx | 113 | −0,365 | 22,1% |
| XAUUSD.vx | 133 | −0,299 | 3,6% |
| GBPUSD.vx | 112 | −0,275 | 24,7% |
| US30.vx | 114 | −0,099 | 7,9% |

EURGBP, NZDUSD dan AUDJPY memiliki friksi besar; XAUUSD dan US30 relatif murah menurut proxy, tetapi tetap negatif. **Masalah teknikal bukan sekadar spread.**

## 4. Solusi: apa yang sudah diimplementasikan

1. **Causal replay diperbaiki:** label stop bar pertama dipertahankan, masa dua jam yang belum lengkap disensor, event historis dan semua kegagalan dicatat; tidak ada harga masa depan yang menjadi input sinyal.
2. **Filter biaya defensif:** `MarketDecisionBrain V3` menolak sinyal jika rasio spread teramati terhadap estimasi risiko stop struktural melewati **20%**. Ini default keselamatan yang dipasang **setelah** riset; bukan angka teroptimasi, dan belum terbukti memperbaiki profit. Filter hanya bisa mengubah sinyal menjadi WAIT.
3. **Alasan penolakan terlihat:** rasio biaya dan status sudah dilanjutkan ke `ContextualDecisionIntelligence` yang sama, tanpa AI Brain kedua.
4. **Pencatatan kegagalan permanen:** `closed_bar_failure_forensics.py`, harness replay asli, `aggregate_closed_bar_forensics.py`; semua label tetap masuk denominasi dan file mentah disimpan di VPS secara privat.
5. **Jalur aman:** GitHub Body CI PASS; VPS tes PASS; observer hanya satu setiap 5 menit, tanpa order live.

## 5. Solusi berikutnya yang harus diuji secara independen — BELUM diloloskan

| Masalah terbukti | Hipotesis perbaikan yang perlu diuji terlebih dahulu | Bukti minimum |
|---|---|---|
| RANGE_FADE berhenti terlalu cepat | Baru pertimbangkan entry setelah liquidity sweep + candle M5 reclaim di sisi range yang valid pada M15/H1; objective awal ke **titik tengah range**, bukan otomatis resistance H1 terjauh | Tick BID/ASK untuk urutan sweep, entry dan exit; sampel baru per BUY/SELL |
| BREAKOUT_RETEST kebanyakan TIME dan SL jauh (~3,2–3,5 ATR M15) | SL berdasarkan swing retest dekat yang sah, entry hanya setelah retest bertahan, target dari struktur nyata; jika RR setelah biaya tidak sesuai maka WAIT | Simulasi SL/TP pada tick nyata dan perbandingan tanpa mengubah aturan pasca-hasil |
| TREND_PULLBACK target jarang disentuh | Syarat pullback selesai: struktur H1 searah, konfirmasi M15 dan M5, invalidasi pada swing yang diuji, target bertahap 1R versus resistance/support yang benar | Pengujian pre-committed pada tanggal berbeda dan biaya lebih konservatif |
| Seluruh metode rata-rata gerak menguntungkan kecil | Uji horizon exit terpisah 30 / 60 / 120 menit dengan risiko dan biaya broker sama; evaluasi TIME setelah faktor spread dan slip | Data *future* yang belum digunakan untuk mengubah model |
| Berita/policy historical tidak tersedia point-in-time | Jangan klaim analisis fundamental historis atau arah kebijakan jika artikel/kalender yang tersedia saat itu tidak dapat dibuktikan | Arsip tanggal publikasi, isi penuh, waktu observasi, mekanisme dampak USD/rates/asset |

**Larangan ilmiah:** jangan mencari ambang spread/SL/TP terbaik di 1.964 hasil ini lalu menyebutnya edge baru. Cara seperti itu mendorong *backtest overfitting*. Versi alternatif harus dibekukan sebelum diuji pada data tanggal/rezim berikutnya yang belum digunakan dalam pemilihan model.

## 6. Verifikasi deployment

- Unit tests khusus error path, first candle, full horizon, spread-risk protective guard, kode review agregasi: PASS.
- GitHub Body CI [PASS run 38293407912](https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions/runs/38293407912) pada source `e21e0e96d60549e7656b28f46cc93e5445564fda`.
- Satu smoke MT5 nyata dari observer sesudah perubahan: **17 instrumen, 17 WAIT, 0 order live, clock acuan `MT5_HISTORICAL_TICK_TIME_MSC_UTC`**. Dua observer lama tetap nonaktif dan observer utama dipulihkan.
- Detail individu 1.964 kandidat tidak disebar ke GitHub: `C:\KatarinaDev\artifacts\contextual-observer\diagnostic-sept-batch1..4.json`, `diagnostic-oct-batch1..4.json`, `katarina-verified-forensic-17-market-sep-oct.json` (private VPS).

## Referensi

- [MetaQuotes: MT5 Python copy_rates_from_pos — historis OHLC, `spread`, dan keterbatasan jumlah bar](https://www.mql5.com/en/docs/python_metatrader5/mt5copyratesfrompos_py).
- [MetaQuotes: MT5 Python copy_ticks_range — BID/ASK, penggunaan timestamp UTC](https://www.mql5.com/en/docs/python_metatrader5/mt5copyticksrange_py).
- [Bailey dan López de Prado: How Backtest Overfitting in Finance Leads to False Discoveries, Significance (2021)](https://academic.oup.com/jrssig/article/18/6/22/7038278).
- [Bailey dkk.: Probability of Backtest Overfitting (2015)](https://escholarship.org/uc/item/4w1110bb).
- [Claeys, When Backtests Guess (2026): ambiguitas urutan high/low OHLC](https://ssrn.com/abstract=6240638).

**Kesimpulan:** KATARINA lebih aman dan bisa mengidentifikasi kegagalan secara spesifik, tetapi *belum ada strategi yang terbukti profitable*. Hasil yang telah diperiksa adalah hipotesis yang harus berhadapan dengan bukti baru, bukan izin trading live.
