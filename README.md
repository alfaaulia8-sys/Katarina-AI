# KATARINA AI

**Analisis lebih terarah. Keputusan lebih disiplin.**

KATARINA AI adalah proyek yang dikembangkan untuk membantu pengamatan pasar, evaluasi strategi, dan pengambilan keputusan yang lebih sistematis.

## Tentang proyek

Fokus KATARINA AI adalah menghadirkan pengalaman analisis yang praktis, terukur, dan memperhatikan risiko. Pengembangan dan pengujian masih berlangsung.

## Status perkembangan — 15 Oktober 2026

**Development Preview / research-only. Live trading belum diaktifkan.**

| Bagian | Terverifikasi setelah integrasi PR #86 |
|---|---|
| Otak unified | 10 komponen canonical terintegrasi; 0 order dalam uji offline |
| Pengujian | 1.309 unit, 110 static (4 skipped), 42 integration lulus |
| Repository | Main dilindungi; wajib PR dan CI; 0 kolaborator tambahan |
| Cleanup | 42 branch lama diintegrasikan dan dihapus; hanya `main` tersisa |
| Sinkronisasi | GitHub dan checkout kerja cocok; VPS belum diverifikasi |
| Akses luar Work | Panduan tersedia; login CLI perangkat tujuan belum terpasang |

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
