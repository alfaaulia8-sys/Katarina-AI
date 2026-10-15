# KATARINA AI

**Analisis lebih terarah. Keputusan lebih disiplin.**

KATARINA AI adalah proyek yang dikembangkan untuk membantu pengamatan pasar, evaluasi strategi, dan pengambilan keputusan yang lebih sistematis.

## Uji langsung di komputer

Windows: ekstrak source, jalankan **SETUP_KATARINA.bat**, lalu **START_KATARINA.bat**.
Uji awal memakai data buatan tanpa MT5/VPS dan menghasilkan laporan HTML lokal.
[Petunjuk uji PC dan MT5 baca-saja](docs/QUICKSTART_PC.md). Live tetap OFF.

## Tentang proyek

Fokus KATARINA AI adalah menghadirkan pengalaman analisis yang praktis, terukur, dan memperhatikan risiko. Pengembangan dan pengujian masih berlangsung.

## Status perkembangan — 16 Oktober 2026

**Development Preview / research-only. Live trading belum diaktifkan.**

| Bagian | Satu otak canonical — pembaruan 16 Oktober 2026 |
|---|---|
| Otak unified | 1 otak, 17 modul canonical; Management dan 11 spesialis dihapus |
| Pengujian | 1.274 unit, 113 static (4 skipped), 132 integration lulus |
| Repository | Main dilindungi; wajib PR dan CI; 0 kolaborator tambahan |
| Cleanup | 42 branch lama diintegrasikan dan dihapus; hanya `main` tersisa |
| Sinkronisasi | GitHub dan checkout kerja cocok; VPS belum diverifikasi |
| Akses luar Work | Panduan tersedia; login CLI perangkat tujuan belum terpasang |

[**Diagram patokan dan jalur implementasi**](docs/architecture/KATARINA_SINGLE_BRAIN_WORKFLOW_20261016.md) ·
[**Lihat status lengkap dan bukti**](docs/PROJECT_STATUS.md) ·
[**Lihat perubahan**](CHANGELOG.md) ·
[**Lanjutkan pekerjaan**](docs/CURRENT_PROJECT_HANDOFF.md) ·
[**Akses GitHub lintas perangkat**](docs/operations/GITHUB_ACCESS.md)

Angka tersebut adalah snapshot bertanggal. Hasil terbaru tersedia di
[GitHub Actions](https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions).
Lulus pengujian sumber tidak membuktikan profitabilitas atau kesiapan trading live.

## Informasi

- [Perkembangan proyek](https://github.com/alfaauliau-katarinaAI/Katarina-AI/commits/main)
- [Status pengujian](https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions)
- [Laporkan kendala](https://github.com/alfaauliau-katarinaAI/Katarina-AI/issues)

> **Perhatian:** Pasar keuangan memiliki risiko kerugian. Tidak ada jaminan hasil atau keuntungan. Gunakan lingkungan pengujian terlebih dahulu dan jangan membagikan kredensial akun.

## Pendanaan riset & kerja sama teknis

- [**KATARINA AI Research & Sponsorship — situs publik**](https://katarina-research.vercel.app/) (bisa dibaca tanpa login).
- Terbuka untuk pembahasan sponsor infrastruktur (VPS/data), riset yang dibiayai dengan ruang lingkup tertulis, serta jasa evaluasi sistem Python/MT5 dan laporan pengujian yang disepakati.
- **GitHub Sponsors masih dalam peninjauan** per 11 Oktober 2026. Belum ada tautan pembayaran sponsor aktif, paket berbayar yang sudah dijual, atau dana yang diterima melalui halaman ini.
- KATARINA AI masih **development preview**. Belum terbukti menghasilkan profit stabil, belum siap ditawarkan sebagai robot trading live, dan bukan produk investasi atau janji imbal hasil. Semua angka kinerja harus berasal dari pengujian yang dapat direproduksi.
- Hubungi: [email kerja sama](mailto:alfaaulia8@gmail.com?subject=KATARINA%20AI%20Research%20Collaboration).


## Layanan dan paket yang direncanakan

- [**KATALOG KATARINA — early access, belum menerima pembayaran**](website/plans.html): rencana akses gratis, paket riset premium, dan lisensi EA ketika selesai divalidasi. Harga bersifat indikatif, bukan penawaran transaksi aktif.
- [**Konsultasi dan jasa teknis**](mailto:alfaaulia8@gmail.com?subject=KATARINA%20AI%20Technical%20Services%20Quote): pengujian Python/MT5, QA data, integrasi non-trading, dan dokumentasi dengan penawaran tertulis.
- [**Kemitraan riset/infrastruktur**](website/sponsors.html): kontak awal, bukan checkout GitHub Sponsors.
- TIDAK menerima pembayaran paket langganan atau lisensi EA sampai produk, ketentuan penggunaan, verifikasi pembayaran, dan dukungan pelanggan siap. Tidak ada jaminan hasil trading.


## Catatan teknis dan riwayat validasi

- [Laporan validasi jalur, kode MT5, dan observer](docs/validation/2026-10-11-paths-mt5-integration.md).
- [Audit struktur dan dependensi otomatis](scripts/governance/audit_dependency_links.py) diperiksa di GitHub Actions. Ini adalah pemeriksaan sumber, **bukan** bukti kesiapan live.
- [Snapshot tahap 11 Oktober](docs/operations/GITHUB_FIRST_STATUS_20261011.md) — riwayat, bukan status terkini.

## Navigasi pengembangan

- [Aturan pengembangan dan validasi](docs/operations/GITHUB_FIRST_DEVELOPMENT.md).
- [Audit cleanup dan sinkronisasi sumber](docs/operations/REPOSITORY_CLEANUP_20261015.md).
- [Checkpoint historis sampai 13 Oktober](docs/handoff/KATARINA_START_NEXT_CHAT_20261013.md) — bukan status VPS terkini.
- [Panduan hosting Cloudflare Pages](docs/deployment/CLOUDFLARE_PAGES_SETUP.md).

## Portabilitas host — 16 Oktober 2026

Otak dapat menjalankan satu siklus riset lokal tanpa VPS/MT5 melalui
`run_contextual_market_observer.py --offline-research`. `--doctor` memeriksa host;
lokasi state mengikuti konfigurasi/OS, anggaran observasi mengikuti kapasitas.
Lihat [panduan host portabel](docs/architecture/KATARINA_PORTABLE_HOST.md). Tidak ada migrasi state legacy otomatis,
Cloud Hands lintas host belum terverifikasi, live tetap OFF.

## Koneksi otomatis baca-saja — 16 Oktober 2026

Launcher memilih local/cloud/offline menurut konfigurasi akun yang diizinkan.
Retry terbatas mengulang seluruh pass; tanpa koneksi valid tetap riset lokal.
Sensor HTTPS baru memerlukan pemasangan dan kredensial sekali; belum diuji pada
MT5/cloud nyata. Lihat [kontrak koneksi otomatis](docs/architecture/KATARINA_AUTOMATIC_CONNECTION.md). Risk Governor independen, live OFF.

## Pemulihan environment privat — 16 Oktober 2026

Startup memeriksa dependensi dan menguji kandidat pengganti sebelum memilihnya.
Environment lama, strategi, Risk Governor dan memori tetap dipertahankan; tidak
ada perubahan source atau izin trading. Panduan: [pemulihan environment](docs/architecture/KATARINA_ENVIRONMENT_RECOVERY.md). Live OFF.

### Dialog and AI trading pretrial (LIVE OFF)

`python katarina_pc.py pretrial` runs synthetic behavior acceptance.
`python katarina_pc.py chat --model-config PATH` opens the configured model dialog;
`ui` opens the optional foreground authenticated browser service. Model IDs,
credentials and real MT5 connections require installation configuration.
MT5 feedback is WAIT/ACK only, not an executable order transport.
[Setup, target diagram and remaining real-evidence gates](docs/architecture/KATARINA_AI_TRADING_PRETRIAL.md).
