# Perubahan material Katarina AI

## 2026-10-15 — seluruh branch disatukan ke main

- PR #85 menyatukan ancestry 34 branch yang patch-nya sudah terwakili di main
  atau seluruh blob file perubahannya identik dengan main.
- PR #86 mengintegrasikan Neuro-Link recall, riset shadow paper/replay dan
  penelitian portfolio; varian engine eksperimen dipisahkan ke modul research.
  Jalur recall baru tetap memakai pemeriksaan checksum payload yang ada.
- Empat branch lama memakai main yang sudah lebih lengkap/diperkuat. Ekstraksi
  website didokumentasikan tanpa menghapus 799 file inti dari repository unified.
- Body CI PR dan main lulus: 1.309 unit, 110 static (4 skipped), 42 integration.
- Guarded cleanup menghapus seluruh 42 branch awal selain main dalam lima batch:
  10 + 10 + 10 + 10 + 2. Daftar branch diverifikasi setelah tiap eksekusi.
- Seluruh 42 head awal tersimpan sebagai ancestor main; main tetap dilindungi.
  Engine produksi, Risk Governor, konfigurasi risiko dan MT5 tidak berubah;
  live trading tidak diaktifkan. Sinkronisasi VPS belum diverifikasi.
- README, status proyek dan handoff diperbarui dengan tautan audit/receipt.

## 2026-10-15 — repository, akses dan status (snapshot sebelumnya)

- PR #81 menghapus empat snapshot VPS kedaluwarsa, menyamakan default repository
  pada installer/bridge, memindahkan dua dokumen, dan menambah guard kebersihan.
- PR #82 memulihkan executable bit agent Termux yang terdeteksi berubah saat
  publikasi. Source agent tidak diubah oleh koreksi metadata tersebut.
- PR #83 memperbaiki CODEOWNERS, mempin lima Actions resmi ke commit SHA,
  menghapus dispatch audit ganda, membatasi izin dan memperkuat guarded cleanup.
- Main dilindungi: wajib PR/body CI/up-to-date/resolved conversations, admin ikut
  aturan, force push dan penghapusan main ditolak. Tidak ada kolaborator tambahan.
- Secret scanning, push protection, dependency graph, Dependabot alerts dan
  pelaporan kerentanan privat diaktifkan. Approval bot dinonaktifkan.
- Cleanup terverifikasi menghapus 10 lalu 2 branch ancestor, menyisakan main dan
  42 branch unik. Dry-run penutup tidak menemukan kandidat.
- Scheduled news menghasilkan artifact untuk publikasi yang direview, bukan
  mendorong langsung ke main. Workflow stage/research manual dipertahankan.
- Verifikasi offline unified brain: 10 komponen terintegrasi, tidak ada order,
  live execution false. Strategi/Risk Governor tidak diubah.
- Dokumentasi status kini dipusatkan di `docs/PROJECT_STATUS.md`; handoff lama
  dipindahkan ke arsip bertanggal dan panduan CLI dipisahkan dari koneksi Work.

Angka pengujian dan tautan bukti ada di [status proyek](docs/PROJECT_STATUS.md).
Perubahan ini tidak mengklaim sinkronisasi VPS atau profitabilitas strategi.
