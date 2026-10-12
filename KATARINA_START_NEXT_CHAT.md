# KATARINA AI — START NEXT CHAT

**Checkpoint: 12 Oktober 2026 | Version: V6 | Status: riset-only / WAIT.**

Dokumen ini adalah sumber utama untuk memulai chat baru. Jangan menganggap strategi sudah profitable. Jangan gunakan data 2025–Oktober 2026 sebagai holdout independen karena sudah diteliti berulang kali. **Hanya lakukan pekerjaan baru jika diminta pengguna.**

## Tujuan yang telah ditetapkan

- Pemilihan opportunity terbaik secara simultan dari **maksimum 17 instrumen pilihan yang tersedia di broker** (7 major, 5 cross, XAUUSD, BTCUSD, OIL, US30, US100), tidak mengandalkan satu market; tidak memaksakan transaksi setiap hari. **Riset historis lama** tetap pada 55 pair.
- **Intraday first** sebagai strategi utama. **Scalping hanya opsi ekstrem** yang harus diuji mandiri, dan **default DISABLED** karena hasilnya masih negatif.
- Risk-aware, tidak ada otorisasi pengiriman trading live; ketika data, news, risiko, eksekusi atau evidence tidak cukup: **WAIT**.
- Preferensi komunikasi: bahasa Indonesia, langsung hasil dan status, tanpa penjabaran proses panjang.

## Hasil historis kumulatif (semua model, bukan realized broker P/L)

| Tahap | Sampel / strategi | Avg net R | Profit factor | Keputusan |
|---|---|---:|---:|---|
| Baseline 55 pair | 8.310 event, sampling 1/36 M5 | -0,20509 | 0,7008 | Rugi |
| Structural Entry V1 | 1.241 event | -0,15169 | 0,7741 | Selektif, masih rugi |
| Exit V2 3-pair | 203 event | -0,07575 | 0,8815 | Tolak penerapan universal |
| Semantic Setup V3 | 731 event | -0,14473 | 0,7847 | Definisi setup benar, tetapi masih rugi |
| Daily Multi-Pair V4 | 187 transaksi, 67 hari positif | -0,073 | 0,885 | Return model -3,47% |
| Full M5 Intraday V5 | 658 transaksi, prefilter scanner saja | +0,00556 | 1,009 | Return +0,58% model saja; +0,10R biaya => -14,68% |
| Extreme Scalp V5 | 155 transaksi | negatif | 0,702 | Return -2,58% model; DISABLED |
| **Full M5 + Brain V6** | **565 transaksi** | **-0,03744** | **0,9416** | **Return model -5,4351%; maks DD model 19,6548%** |
| V6 +0,10 R extra cost | 565 transaksi | -0,13744 | 0,8049 | **Return model -17,8946%** |
| V6 control alfabetis | 564 transaksi | -0,03025 | 0,9526 | Return -4,4637%; ranking Brain belum lebih baik |

**V6** telah menguji **55 pair**, memindai **4.841.516 candle M5 tertutup**, menghasilkan **39.691 kandidat scanner**, **1.590 lolos semantic, structural-quality dan keputusan Brain**, dan **565 trade portofolio**. Pada **329 hari pasar** historis: **165 hari profit**, **145 hari rugi**, **19 tanpa transaksi**. Hanya **6/16 bulan** yang positif.

Angka ini diperoleh dengan model risk 0,25%/entry dan asumsi spread/slippage/bar-fill; bukan pertumbuhan modal yang bisa direplikasi di akun real tanpa validasi broker.

## Masalah yang telah ditemukan

1. Label playbook lama mengakui fake pullbacks dan breakout tanpa retest. SemanticSetup memperbaiki definisi closed-candle tetapi *tidak menghasilkan edge secara otomatis*.
2. Banyak kandidat V6 ditolak: no_pullback_location **24.386**, insufficient_structural_room **8.422**, Brain disagreement on direction **2.138**.
3. V5 scanner dan full Brain sebelumnya tidak sepakat. V6 telah menyatukan scanner + pemeriksaan semantik + entry quality + keputusan Brain **sebelum** cross-pair ranking. Hasil gabungannya **lebih buruk** dari V5.
4. Perbandingan ranking V6 melawan pemilihan alfabetis pada jam yang sama **belum menunjukkan keunggulan**.
5. Biaya komisi broker historis **belum terkalibrasi**. Audit akun 120 hari hanya **1 deal** tanpa data komisi per pair. Audit tick spot-check: hanya **13 dari 16** permintaan historis tersedia dekat target waktu pada 4 instrumen.
6. Minimum lot, historical tick fill, margin, swap, conversion P/L dan news blackout historis belum dipastikan. Skenario modal $1k/$5k hanyalah diagnosis, tidak membuktikan implementasi nyata.
7. MT5 broker raw timestamp sekitar UTC+3 pada 12 Okt 2026; histori zona waktu dan DST **belum** divalidasi. Jangan klaim slot laporan sudah UTC/WIB benar.
8. Data historis yang pernah dipakai memutus independensi evaluasi; **0 closed trade baru** dari snapshot awal pengumpulan forward setelah freeze.

## Status kode, pengujian, dan keamanan

- Branch utama GitHub: **main**, repo **alfaauliau-katarinaAI/Katarina-AI**.
- Sebelum checkpoint, HEAD teruji: **5b5d8b4b80ea2a4874e4939019a809856da2b6e3**.
- Lokal VPS **753 unit tests, 96 static tests, 22 integration tests PASS**.
- Di GitHub seluruh 3 workflow: **Operational Hardening, Stage 10-40 Baseline, Body CI PASS**.
- MT5 telah dikonfirmasi **trade_allowed=False**; **0 live orders**. Jangan mengubah Risk Governor atau mengaktifkan live tanpa dasar.
- **Intraday RESEARCH-ONLY**, **Scalp DISABLED**, tindakan saat tanpa data/news/risk terverifikasi: **WAIT**.
- **Brain masih rules-based/explainable**, bukan trained model dengan probabilitas kemenangan terkalibrasi.

## Lokasi penting dalam repository

- docs/research/KATARINA_BRAIN_UNIFIED_INTRADAY_V6_20261012.md
- docs/research/KATARINA_FULL_M5_INTRADAY_SCALP_V5_20261012.md
- docs/research/KATARINA_MULTI_PAIR_DAILY_RANK_V4_20261012.md
- docs/research/KATARINA_ROOT_CAUSE_AND_SEMANTICS_V3_20261012.md
- docs/research/KATARINA_ENTRY_EXIT_V2_AUDIT_20261012.md
- docs/research/KATARINA_ENTRY_BRAIN_STRUCTURAL_55_PAIR_20261012.md
- docs/research/outputs/20261012/brain_unified_intraday_v6_full.json
- docs/research/outputs/20261012/brain_unified_intraday_v6_trades.csv
- docs/research/outputs/20261012/brain_unified_intraday_v6_forward_contract.json
- src/katarina/intelligence/unified_intraday_gate.py
- src/katarina/intelligence/intraday_scalp_research.py
- src/katarina/intelligence/market_decision_pipeline.py
- src/katarina/intelligence/semantic_setup_truth.py
- src/katarina/intelligence/structural_entry_quality.py
- src/katarina/intelligence/research_readiness_gate.py
- scripts/research/backtest_unified_intraday_brain_v6.py
- scripts/research/collect_forward_intraday_v6.py

VPS: **C:\KatarinaDev\ci-research-fresh-20261012** (checkout BERSIH dan tersinkron dengan GitHub main; gunakan ini untuk pekerjaan berikutnya). **C:\KatarinaDev\ci-research** adalah checkout LAMA yang tidak sepenuhnya dapat di-reset akibat akses beberapa file ditolak; jangan gunakan sebagai sumber kerja atau menghapusnya tanpa menyelesaikan masalah izin., **C:\KatarinaDev\brain-runtime\Scripts\python.exe** (runtime dengan MT5), **C:\KatarinaDev\decision-backtest-20261012** (keluaran test), **C:\KatarinaDev\handoff-backups** (snapshot cadangan privat). Jangan upload kredensial, trade account ID, history broker pribadi, cache browser atau file privat ke GitHub.

## Kondisi cleanup

- Main GitHub sebelum checkpoint punya **1.054 item tree**, tidak ada tracked file >1 MB maupun folder cache Python/node_modules/venv/pyc yang ditemukan.
- Branch penelitian dan web masih punya commit *diverged/unmerged* dan harus dipertahankan: **research/brain-intelligence-admission-20261011**, **research/portfolio-regime-audit-20261011**, **web/standalone-extraction**. Jangan menghapus pekerjaan yang belum merged.
- Workspace VPS lama sempat tidak sinkron dengan main. Snapshot recovery privat telah diverifikasi di **C:\KatarinaDev\handoff-backups\ci-research-pre-github-sync-20261012.zip** (3,483 MB, 963 berkas, SHA256 b2dfcfcc78476c4d4c89c3a58026d7980b8c3ee1083b06eb3fe190cdf6f58bb6). Ini bukan artefak publik.
- VPS hanya ~2 GB RAM. Layanan MT5, Chrome dan website jangan dihentikan atau datanya dihapus tanpa perintah khusus. Cache unit/integration/temp regenerable aman dibersihkan.

## Pekerjaan berikutnya bila pengguna memerintahkan

1. Bekukan konfigurasi Brain V6 yang konsisten sebagai **research baseline**. Jangan membiarkan pipeline skrip dan production gate berbeda.
2. Kumpulkan observasi **forward yang benar-benar baru** setelah freeze, lengkap dengan biaya, eksekusi, batas margin/lot dan validitas berita. Jangan menyatakan riset atas tape 2025–Oktober 2026 sebagai OOS.
3. Uji robustitas lintas pair berdasarkan expectancy R net-of-cost, PF, DD akun, korelasi exposure, win days vs no-trade days, dan kestabilan regime/bulan.
4. Uji scalp secara independen dan tetap disabled hingga menghasilkan bukti berulang yang sah.
5. Jalur LIVE hanya bisa dipertimbangkan setelah bukti independen yang kuat, tanpa mengubah risk governor sembarangan.

**Kalimat chat baru:** "Lanjutkan KATARINA dari KATARINA_START_NEXT_CHAT.md di main GitHub. Cek status saja dahulu; jangan mengerjakan apa pun selain yang saya perintahkan."

**Tidak ada profit harian yang dijamin. Keputusan NO_TRADE dapat menjadi keputusan yang optimal.**

## 8. HASIL CLEANUP TERAKHIR (VERIFIKASI 12 Oktober 2026)

- **GitHub:** checkpoint V1–V6 di main; tidak ada tracked file >1 MB dan tidak ada cache build/test tracked. Ketiga branch lama dipertahankan karena commit unik belum merged. Tidak ada data riset atau commit dibuang.
- **VPS kode:** bersih pada checkout baru **C:\KatarinaDev\ci-research-fresh-20261012**; main GitHub SHA **0e643838b3fe546ba68e0c9789ada814dd1b157a** saat clone. Git status clean dan handoff tersedia. Test pada fresh checkout: **752 unit, 96 static, 22 integration PASS**.
- **VPS lama:** akses ditolak pada beberapa file checkout **C:\KatarinaDev\ci-research** sehingga reset/rename terhenti. Checkout lama sengaja tetap disimpan, bukan diam-diam dihapus atau dinyatakan bersih. Snapshot ZIP sebelum percobaan reset telah diuji integritas dan disimpan privat.
- **Safe cleanup:** **66 cache Python/test regenerable, sekitar 4,465 MB**, dihapus dari enam direktori code workspace, tanpa error. Skrip helper sementara untuk perpindahan yang tidak lagi dibutuhkan dibersihkan. Data tick/historical broker, hasil penelitian dan website tetap utuh.
- **VPS status:** RAM tersedia **220 MB dari 2.047 MB**, ruang disk tersedia **9,32 GB**; **tidak ada backtest aktif**, MT5 tetap berjalan. RAM tetap rendah terutama karena aplikasi MT5 dan Chrome yang sengaja tidak dimatikan.
- **GitHub Body CI** pada commit checkpoint **0e643838** sukses. Lihat laporan cleanup privat **C:\KatarinaDev\state\handoff_cleanup_20261012.json** untuk daftar cache.
- Ini **bukan** janji semua VPS menjadi ringan sepenuhnya: RAM tidak akan meningkat signifikan tanpa menutup aplikasi atau menambah RAM. Aplikasi aktif tidak disentuh untuk menghindari gangguan.

## 9. BATAS SCANNER BARU (12 Oktober 2026)

- Scanner operasional dan default replay V6 berikutnya memakai **maksimum 17 instrumen**: 7 major FX, 5 cross FX, XAUUSD, BTCUSD, oil, US30, US100. Semua simbol tetap diperiksa terhadap katalog broker aktif; yang tidak ada/disabled otomatis dilewati, tanpa membuat simbol palsu.
- Pada audit read-only VPS, **17/17 tersedia dari katalog 74**; oil = `XTIUSD.vx`, US100 = `NAS100.vx`. Tidak ada order dikirim.
- Resolver dan tes ada di `src/katarina/intelligence/broker_scan_universe.py` dan `tests/unit/intelligence/test_broker_scan_universe.py`; rincian di `docs/operations/BROKER_ADAPTIVE_SCAN_SCOPE_20261012.md`.
- Data hasil V1–V6 tetap arsip 55 pair dan **tidak boleh dipresentasikan sebagai performa 17 instrumen**. Risk Governor, permission live, dan hasil forward independen tidak berubah.


## 10. ADAPTIVE RESEARCH DI GITHUB ACTIONS (12 Oktober 2026)

- Jalur adaptif baru: src/katarina/intelligence/adaptive_walkforward.py dan adaptive_strategy_library.py, plus tes dan workflow .github/workflows/adaptive-brain-research.yml. Detail di docs/research/KATARINA_ADAPTIVE_RESEARCH_V7_20261012.md.
- Komputasi dan test di runner GitHub, bukan VPS. Dataset GitHub dari paper trade V6 digunakan untuk diagnosis retrospektif subset simbol, bukan backtest profit metode baru.
- Memori performa belajar hanya setelah exit paper dan memisahkan BUY/SELL, instrumen/keluarga dan kondisi biaya. Risiko hanya simulasi; Risk Governor produksi tetap.
- TREND_PULLBACK, BREAKOUT_RETEST, LIQUIDITY_SWEEP_RECLAIM dan RANGE_MEAN_REVERSION adalah prototipe *hipotesis*, tidak boleh diberi P/L milik trade V6.
- Data 2025–2026 telah diteliti sebelumnya; walk-forward kronologis ini bukan bukti holdout independen. Privat data broker tetap di luar GitHub.
- Output produksi tetap WAIT. Tidak ada pengaktifan LIVE atau penulisan file pada VPS.


### Verifikasi hasil V7 oleh runner GitHub

- Commit kode: f1aa89aefe7f5c1b54d8e777156d10a8faa3f997. **Keempat workflow GitHub PASS**, termasuk Adaptive Research (#38200671468).
- Subset arsip V6: 334 paper trade historis pada 14 instrumen yang pernah tereksekusi dalam model V6; bukan keseluruhan histori kandidat 17 instrumen.
- Adaptive model pada biaya dasar: 70 trade, return **-2,7752%** (pembanding V6 subset kondisional: **-0,3066%**). Biaya tambahan +0,10R: 44 trade, return **-4,1422%**. Belum profitable.
- Prototipe metode alternatif belum punya evaluasi P/L dari candlestick historisnya masing-masing. Jangan menyatakan strategi V7 lolos atau mengaktifkan live.
- Artifact riset tersimpan dalam run Actions (retensi 7 hari). VPS tidak diubah atau ditulis.


## 11. STRATEGY TOURNAMENT CANDLE ASLI — GITHUB RUNNER (12 Oktober 2026)

- Runner baru .github/workflows/public-strategy-tournament.yml, kode scripts/research/public_market_tournament.py, tes tests/unit/intelligence/test_public_market_tournament.py, dokumentasi docs/research/KATARINA_STRATEGY_TOURNAMENT_V8_20261012.md.
- Pengujian diarahkan untuk keluarga Trend Pullback, Breakout Retest, Liquidity Sweep, Range Mean Reversion; BUY dan SELL dipisah. Pilot pertama EURUSD + XAUUSD menggunakan M1 BID/ASK **publik** dari Dukascopy, bukan file privat broker VPS, dengan agregasi M5/H1 tertutup dan entry candle berikutnya.
- Broker live, Risk Governor, penulisan dan restart VPS semuanya tidak disentuh. GitHub runner menggunakan permission contents:read. Arsip M1 mentah tidak ditulis ke GitHub, hanya diagnostic summary dan modeled paper events sementara.
- Status edge/profit harus mengikuti hasil runner, bukan klaim sebelum tes. Semua historical paper tetap RESEARCH-ONLY / WAIT.


### Uji pertama Strategy Tournament V8 — diverifikasi GitHub (12 Oktober 2026)

- GitHub Actions PASS: https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions/runs/38202938538
- Data publik M5 referensi (bukan BID/ASK nyata broker), rentang 2026-08-17 s.d. 2026-09-08: EURUSD 4894 M5, XAUUSD 4683 M5.
- Empat metode, BUY/SELL terpisah: 674 transaksi simulasi yang **boleh overlap**, semua 8 kelompok method/side mean R negatif. Pool -0,163411 R, PF 0,73002 — **bukan return portofolio investable**.
- Dukascopy BID/ASK asli tidak berhasil diambil via runner karena TLS timeout. Sumber alternatif M5 berhasil, dengan asumsi spread model yang harus dipisah dari evidence broker. VPS tidak ditulis.
- Belum ada strategi profitable yang tervalidasi; 15 instrumen lain belum diuji pada pipeline baru. Tetap RESEARCH-ONLY/WAIT, live trading disabled.


### Ekspansi uji V8-B (GitHub-only)

- 11 sumber M5 publik terverifikasi: EURUSD, GBPUSD, USDJPY, AUDUSD, USDCAD, EURGBP, EURJPY, XAUUSD, USOIL, US30, NAS100. Enam belum ada sampel M5 cocok: USDCHF, NZDUSD, GBPJPY, AUDJPY, EURAUD, BTCUSD (bukan berarti broker tidak punya).
- Runner GitHub Actions dipecah 4 kelompok, peristiwa Juni–Agustus 2026, dengan ringkasan per strategi/BUY-SELL per bulan dan +0,10/+0,20 R biaya asumsi.
- Model tetap menggunakan OHLC referensi publik, **ASK/spread hanya asumsi**; belum broker-tick-validated maupun independent unseen holdout.
- Ada agregator hasil sementara; research-triage gate mensyaratkan minimal 20 trade/bulan dan PF >=1,20 serta rata-rata R >=+0,10 pada ketiga bulan setelah +0,10R biaya tambahan. Lulus triase BUKAN izin live.
- VPS tidak diubah. Angka baru harus diisi setelah runner benar-benar PASS.


### VERIFIKASI AKHIR V8-B — 11 pasar / Juni–Agustus 2026

- RUNNER PASS 5/5: https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions/runs/38204091035 . Body CI + Operational Hardening + Stage 10-40 Baseline commit sama juga PASS.
- 11 sumber M5 publik = 3995 paper event **overlap**; 88 grup strategi/instrumen/BUY-SELL di-screen, **0 lulus** kriteria konsistensi 3 bulan setelah biaya tambahan +0,10R.
- Positif tetapi **tidak signifikan**: AUDUSD 4 trade +0,386R, USDCAD 3 trade +0,087R, EURJPY 19 trade +0,126R. XAUUSD 1331 trade -0,1729R, Oil 390 -0,2204R, US30 934 -0,2428R, NAS100 1267 -0,2298R.
- Detail angka dan batas interpretasi di docs/research/KATARINA_STRATEGY_TOURNAMENT_V8_20261012.md. Data tersebut **bukan** BID/ASK broker, spread simulasi dan tidak lolos holdout baru. Enam simbol lain belum punya sampel M5 publik setara.
- Status resmi: RESEARCH-ONLY / WAIT. Tidak ada promosi strategi, order live, write VPS, atau perubahan Risk Governor.


### V9 — broker-read actual M5 + spread, TWO new entry methods (12 October 2026)

- Read-only broker diagnostic on **17 broker symbols**, period June–August 2026; run script `scripts/research/broker_entry_diagnostics_v9.py` (sha `0b300ca`), loaded directly in VPS Python memory, **no VPS files written**.
- 6,557 overlapping modeled events: V8 4329, new V9 2228; mean baseline **-0.150738R**, extra cost +0.10R **-0.250738R**. 0 groups meet robust all-3-month screen, NOT profitable and NOT independent OOS.
- FX M5 spread/ATR median often >0.50; EURGBP 1.57396, oil XTIUSD 0.81395. This calls for cost-aware higher timeframe research, not raising risk.
- Two XAUUSD SELL methods positive only very weak after cost stress, fail monthly consistency, not production eligible.
- Sanitized full aggregate: `docs/research/outputs/20261012/broker_entry_v9_aggregate_sanitized.json`. Report: `docs/research/BROKER_ENTRY_DIAGNOSTICS_V9_20261012.md`.
- GitHub Actions V9 safety and Body CI PASS. No real orders, VPS file edits, private datasets, Risk Governor changes or live authorization. Continue RESEARCH-ONLY/WAIT.


### V10 — Multi-timeframe M15/H1, RR SL risk, broker M15-H4 (12 Oktober 2026)

- Kode riset terisolasi: `scripts/research/broker_multitf_risk_v10.py` at commit `8778c7d`. Menjalankan broker read-only via source in-memory VPS; VPS files/services tidak disentuh. Periode TRAIN Juni-Juli, DIAGNOSTIC Agustus-September 2026 (sudah pernah diteliti: BUKAN unseen holdout).
- 1264 kombinasi asset/timeframe/entry/SL/TP, 9 lolos TRAIN, **0 lolos diagnostic**. Semua belum profitable robust. 13604 kandidat sinyal mentah.
- Simulasi risiko +0,10R biaya tambahan: 0,10% risk 1 posisi -4.0915%, 0,25% risk 1 posisi -7.1036%, 0,50% risk 1 posisi -8.1869%. Risk Governor produksi TIDAK DIUBAH.
- Laporan: `docs/research/BROKER_MULTITF_RISK_V10_20261012.md`. Agregasi mesin tanpa raw broker bars `docs/research/outputs/20261012/broker_multitf_risk_v10_aggregate_sanitized.json`.
- Tetap WAIT/RESEARCH-ONLY, no live orders, no broker data privat upload, no VPS write, tidak mengubah struktur utama KATARINA.


### Final single-study tick verdict, 12 Oktober 2026

- Repo audit: `scripts/research/frozen_xau_sell_tick_verdict.py`; records immutable pinned V9 entry logic.
- XAUUSD SELL Sep15–Oct09 broker BID/ASK ticks:
  TREND_EXPANSION_V9 = 19/21 tick-complete, after-cost +0,310727R,
  PF 1,63904, **PAPER-OBSERVE ONLY** (small, historical, no unseen OOS).
  SWEEP_2C_CONFIRM_V9 = 28/31 complete, -0,403243R,
  PF 0,49123, **REJECT from live-candidate consideration**.
- June–August MT5 historical tick returns empty on sampled dates;
  they were not falsely declared tick-validated.
- Document: `docs/research/FROZEN_XAU_SELL_TICK_VERDICT_20261012.md`.
  Machine result: `docs/research/outputs/20261012/frozen_xau_sell_tick_verdict_aggregate.json`.
- Final project action: **STOP parameter churn, NO LIVE, freeze candidate.
  Collect truly prospective independent paper results before any
  further deployment discussion**. No change to core, VPS files,
  production Risk Governor, orders, MT5 settings.
