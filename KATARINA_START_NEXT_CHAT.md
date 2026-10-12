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
