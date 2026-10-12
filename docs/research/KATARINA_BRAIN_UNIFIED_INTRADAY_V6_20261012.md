# KATARINA V6 — Brain terpadu, full M5, 55 pair

**Hasil: strategi BELUM PROFIT. Status READ-ONLY, WAIT. Tidak ada live order.**

Scanner memindai 4,841,516 closed M5 bar, menghasilkan 39,691 setup intraday, dan 1,590 lolos full Brain + aturan struktur + kualitas entry.

## Performa portofolio multi-pair

| Strategi | Trade | Avg R | PF | Hasil modal model | Maks DD model |
|---|---:|---:|---:|---:|---:|
| V5 scanner tanpa full Brain | 658 | 0.0056 | 1.0093 | 0.58% | 8.33% |
| V6 Brain intraday | 565 | -0.0374 | 0.9416 | -5.44% | 19.65% |
| V6 + 0,10R biaya ekstra | 565 | -0.1374 | 0.8049 | -17.89% | 25.80% |
| V6 + 0,20R biaya ekstra | 565 | -0.2374 | 0.6910 | -28.71% | 31.49% |
| Kontrol pilih pair alfabetis | 564 | -0.0302 | 0.9526 | -4.46% | 18.47% |
| Simulasi modal $1.000, minimum lot | 448 | -0.1094 | 0.8358 | -11.73% | 18.14% |
| Simulasi modal $5.000, minimum lot | 557 | -0.0399 | 0.9381 | -5.69% | 19.96% |

## Hari dan konsistensi

Periode pasar berkode jam broker: 329 hari. V6 entry pada 310 hari: 165 hari positif, 145 negatif, 19 tidak ada entry. Bulan positif 6/16, negatif 10.

| Bulan server broker | Trade | Avg R | PF |
|---|---:|---:|---:|
| 2025-07 | 30 | 0.4841 | 2.0688 |
| 2025-08 | 32 | -0.0023 | 0.9963 |
| 2025-09 | 34 | 0.1191 | 1.1958 |
| 2025-10 | 38 | 0.3508 | 1.7462 |
| 2025-11 | 31 | 0.2656 | 1.5183 |
| 2025-12 | 39 | -0.5546 | 0.3454 |
| 2026-01 | 39 | -0.1315 | 0.8014 |
| 2026-02 | 34 | -0.2369 | 0.6749 |
| 2026-03 | 44 | -0.3572 | 0.5386 |
| 2026-04 | 37 | -0.0417 | 0.9350 |
| 2026-05 | 37 | -0.3997 | 0.4889 |
| 2026-06 | 36 | -0.2076 | 0.7102 |
| 2026-07 | 43 | -0.1678 | 0.7547 |
| 2026-08 | 37 | 0.2622 | 1.5125 |
| 2026-09 | 42 | 0.3478 | 1.7124 |
| 2026-10 | 12 | -0.3317 | 0.5714 |

## Masalah yang dibuktikan

- Penolakan terbesar: no_pullback_location 24,386, insufficient_structural_room 8,422, Brain arah tidak cocok 2,138.
- Scanner, SemanticSetup, StructuralEntryQuality dan full Brain sekarang dikonfirmasi PADA SAAT sinyal tersedia; baru kemudian ranking multi-pair. Pengembalian trade masa depan tidak dipakai memilih posisi.
- Ketika Brain sungguhan dipakai, performa lebih buruk daripada V5. Kontrol alfabetis V6 sedikit lebih baik. Berarti ranking skor belum menghasilkan edge yang konsisten.
- Intraday tetap jalur RISET utama. Scalp ekstrem tetap DISABLED; eksperimen V5 scalping merugikan.

## Biaya real dan audit broker

- 13/16 sampel tick historis tersedia di sekitar waktu target; tidak mewakili seluruh 55 instrumen dan seluruh momen order.
- Riwayat komisi broker 120 hari memberi 1 deal dan 0 simbol dengan statistik komisi, sehingga biaya komisi per lot belum bisa dikalibrasi secara kredibel.
- Simulasi memakai spread M5, one-point adverse fill tiap sisi, serta estimasi biaya +0,03 R. Stress tambahan 0,10/0,20R menunjukkan strategi tidak tahan biaya.
- Skenario modal $1k/$5k memakai spesifikasi lot minimum broker saat ini dan risiko stop setelah fill simulasi: ini DIAGNOSTIK retrospektif, bukan hasil strategi kausal dengan risk sizing dan margin historis terverifikasi.
- Margin, swap, tick intrabar, impact slippage, berita historis, dan offset UTC/DST historis belum tersertifikasi.

## Data baru / forward

- Freeze kontrak paper: 2026-10-12T01:44:05.087731+00:00.
- Snapshot pertama sesudah freeze: 52 pair segar; setup intraday terbaru 0; hasil transaksi baru 0.
- Belum ada untouched independent out-of-sample profit/loss sejak freeze. Seluruh data 2025–Oktober 2026 telah dipakai berulang kali; JANGAN menyebut performa di atas sebagai validasi forward.
- Produk read-only mencatat data dan WAIT; tidak mengizinkan broker orders. Evaluasi hanya boleh berubah setelah bukti baru cukup.

## Keputusan

**INTRADAY RESEARCH ONLY; SCALPING OFF; LIVE WAIT.** Tidak ada strategi yang telah lolos profitable + cost-robust + independent OOS.

Source: src/katarina/intelligence/intraday_scalp_research.py; scripts/research/backtest_unified_intraday_brain_v6.py; scripts/research/collect_forward_intraday_v6.py. Semua file log dan hasil detail disimpan di VPS.