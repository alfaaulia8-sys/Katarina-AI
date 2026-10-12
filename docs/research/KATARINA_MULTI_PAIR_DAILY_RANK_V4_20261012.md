# KATARINA — Sinkronisasi Pencarian Multi-Pair (55 Instrumen)

**Eksperimen read-only; ini bukan bukti sistem profit setiap hari atau izin trading live.**

## Metode yang dibekukan sebelum pengujian

- 55 simbol broker, dievaluasi serentak pada **06:00, 12:00, 18:00 kode waktu broker**. Ini bukan jam UTC yang telah diverifikasi; pengamatan langsung 12 Oktober 2026 menemukan raw tick sekitar 3 jam lebih maju daripada UTC VPS.
- Baca hanya M5/M15/H1 selesai pada waktu penilaian; pilih satu sinyal kualitas terbaik di timestamp itu, tanpa menunggu/melihat hasil sinyal beberapa jam ke depan.
- Kandidat harus disetujui Brain teknis, StructuralEntryQuality dan pemeriksaan definisi playbook (real structure/retest/sweep).
- Ranking memakai skor bukti struktur, ruang menuju target dan spread relatif ATR. Skor bukan probabilitas profit yang terkalibrasi.
- Maksimal **satu entry per tanggal pada kode waktu broker**, satu posisi hipotetis aktif sekaligus, risk **0,25% dari ekuitas** per entry. Tidak ada layering.
- Exit: baseline model M5 next-open, SL 1,2 ATR M5, TP 1,8R, maksimum 24 candle M5 dan estimasi biaya 0,03R.
- Semua simulasi berasumsi berita historis aman (padahal tidak terverifikasi). Keputusan real-time tetap WAIT sampai news dan governor valid.

## Berapa hari ada peluang?

- Pair diuji: **55**.
- Checkpoint dengan setidaknya satu simbol punya data: **1,796**.
- Rata-rata simbol terscan per checkpoint: **29.64**.
- Hari dengan setidaknya satu snapshot: **641**.
- Hari dengan setidaknya satu peluang memenuhi kriteria: **187** (29.17% dari hari teramati).
- Hari yang benar-benar mendapat satu trade simulasi: **187** (29.17%).
- Hari NO TRADE: **454** (70.83%).
- Hari simulasi profit: **67** (10.45% dari seluruh hari teramati).
- Hari simulasi rugi: **120**.
- Checkpoint dengan lebih dari satu kandidat serentak: **59**. Ini mengukur seberapa sering ranking antar-pair bisa dibandingkan secara adil.

## Performa gabungan — bukan proyeksi live

| Metode | Trade | Avg R | PF | Win% | Growth model | Max DD model |
|---|---:|---:|---:|---:|---:|---:|
| Ranking skor KATARINA | 187 | -0.0735 | 0.8850 | 35.8300 | -3.4667% | 5.2917% |
| Kontrol alfabetis, kandidat dan timestamp sama | 187 | -0.1147 | 0.8236 | 34.7600 | -5.3050% | 6.8940% |

Kontrol bukan strategi matang; fungsinya memeriksa apakah skor relatif benar-benar bernilai ketika banyak kandidat hadir bersamaan.

## Stress test biaya tambahan

| Biaya tambahan di atas model 0,03R | Rata-rata R | PF | Return modal model | Drawdown model |
|---|---:|---:|---:|---:|
| 0R | -0.0735 | 0.8850 | -3.4667% | 5.2920% |
| 0,10R | -0.1735 | 0.7534 | -7.8772% | 8.3970% |
| 0,20R | -0.2735 | 0.6442 | -12.0871% | 12.4900% |

## Hasil menurut periode yang sudah pernah diteliti

| Periode | Trade | Mean R | PF |
|---|---:|---:|---:|
| 2025_available | 82 | 0.0492 | 1.0833 |
| 2026_Jan_May | 57 | -0.0353 | 0.9425 |
| 2026_Jun_Oct | 48 | -0.3283 | 0.5628 |

## Rekap entry multipair tiap bulan

| Bulan kode waktu broker | Trade | Avg R | Total R | PF |
|---|---:|---:|---:|---:|
| 2024-09 | 1 | 1.7700 | 1.7700 | - |
| 2024-10 | 1 | 0.4702 | 0.4702 | - |
| 2024-11 | 1 | -1.0300 | -1.0300 | 0.0000 |
| 2025-03 | 1 | -1.0300 | -1.0300 | 0.0000 |
| 2025-04 | 2 | -1.0300 | -2.0600 | 0.0000 |
| 2025-05 | 3 | 0.8367 | 2.5100 | 3.4369 |
| 2025-06 | 3 | -1.0300 | -3.0900 | 0.0000 |
| 2025-07 | 10 | 0.6500 | 6.5000 | 2.5777 |
| 2025-08 | 10 | -0.1900 | -1.9000 | 0.7365 |
| 2025-09 | 12 | 0.0811 | 0.9730 | 1.1476 |
| 2025-10 | 16 | 0.2796 | 4.4743 | 1.6561 |
| 2025-11 | 10 | -0.4700 | -4.7000 | 0.4296 |
| 2025-12 | 12 | 0.0955 | 1.1466 | 1.1590 |
| 2026-01 | 15 | 0.2524 | 3.7862 | 1.5251 |
| 2026-02 | 11 | -0.5106 | -5.6166 | 0.3537 |
| 2026-03 | 12 | 0.1367 | 1.6400 | 1.2275 |
| 2026-04 | 10 | -0.1900 | -1.9000 | 0.7365 |
| 2026-05 | 9 | 0.0088 | 0.0793 | 1.0170 |
| 2026-06 | 11 | -0.0118 | -0.1300 | 0.9820 |
| 2026-07 | 13 | -0.3839 | -4.9900 | 0.5155 |
| 2026-08 | 11 | -0.8707 | -9.5777 | 0.0701 |
| 2026-09 | 9 | 0.3397 | 3.0573 | 1.7421 |
| 2026-10 | 4 | -1.0300 | -4.1200 | 0.0000 |

## Pair terpilih paling sering

| Pair | Kali terpilih |
|---|---:|
| JPN225.vx | 33 |
| XAUUSD.vx | 24 |
| DAX40.vx | 19 |
| US30.vx | 19 |
| XAUEUR.vx | 19 |
| BTCUSD.vx | 10 |
| NAS100.vx | 9 |
| EURUSD.vx | 8 |
| GBPUSD.vx | 6 |
| GBPJPY.vx | 6 |
| EURJPY.vx | 6 |
| FRA40.vx | 4 |
| GBPAUD.vx | 4 |
| XAGUSD.vx | 4 |
| EURAUD.vx | 3 |
| XAGEUR.vx | 3 |
| HK50.vx | 2 |
| USDJPY.vx | 2 |
| GBPNZD.vx | 2 |
| EU50.vx | 1 |

## Batasan dan keputusan

- Historical price series and playbooks already inspected: no independent OOS
- Only three fixed UTC snapshots daily, NOT 288 M5 bars nor all intraday signals
- Date/time uses MT5 bar timestamp; broker UTC/DST not fully reconciled
- No verified historical news, scheduled macro blackout, or broker tick execution
- No margin usage, position-size rounding, instrument leverage or inter-market gap risk
- Fixed-fraction R equity approximates closed-trade outcomes, no daily floating MTM
- News unverified means actual safe production decision remains WAIT
- If zero or too few valid setups, correct action is NO TRADE; profit every day cannot be guaranteed
- 06/12/18 sessions and day/month grouping are encoded broker-clock fields, NOT independently certified UTC. Current +3-hour difference cannot be applied to historical DST without verification.

- Data 2025–2026 telah dipakai untuk riset sebelumnya. **Bukan validasi holdout independen**.
- Hari dikelompokkan berdasarkan tanggal **timestamp historis berkode broker**, bukan kalender Asia/Jakarta maupun UTC tersertifikasi. DST historis broker belum dikalibrasi; jangan mengonversi jam slot ke WIB menggunakan satu offset untuk semua periode.
- Tidak mengukur semua peluang seharian; hanya tiga pengambilan keputusan per hari. Angka profit harian tidak dapat digeneralisasikan.
- Ranking berbasis skor aturan, bukan probabilitas profit terlatih; jangan optimasi atau pilih pair setelah melihat hasil tanpa membekukan model lagi.
- Profit, drawdown dan equity adalah model fixed-fraction 0,25%, bukan P/L broker, belum memvalidasi minimum lot, leverage, margin atau volatilitas gap.
- **Kesimpulan: sistem dapat membandingkan seluruh pair, tetapi tidak boleh memaksa entry setiap hari.**

File lengkap: FINAL_DAILY_RANK_55.json dan ranked_trades.csv (detail pada VPS); compact CSV tersedia di repository.