# Status perkembangan Katarina AI

Diperbarui: **15 Oktober 2026**. Snapshot sumber setelah penghapusan Management
serta penyatuan satu otak canonical. Lihat commit `main` dan Actions untuk SHA
perubahan yang diuji; status ini tidak mengklaim deployment VPS telah sinkron.

| Bagian | Hasil terverifikasi | Batas |
|---|---|---|
| Branch | Hanya `main`; 42 branch awal selain main sudah terhapus | Branch kerja sementara boleh muncul untuk PR berikutnya |
| Integrasi | 34 branch terverifikasi setara/identik; delapan direview dan diselesaikan | Varian eksekusi eksperimen tetap terpisah dari engine produksi |
| Pengujian | 1.270 unit, 109 static (4 skipped), 49 integration lulus | Tidak membuktikan kesiapan live atau profitabilitas |
| Otak unified | 1 otak dengan 14 modul canonical; persepsi, kognisi dan Neuro-Link berbagi runtime | Memori privat dan proses VPS belum diperiksa |
| Trading | Engine produksi, Risk Governor, konfigurasi risk dan MT5 tidak berubah | Live execution false; 0 order pada verifikasi offline |
| Keamanan | Main wajib PR/body CI, up-to-date dan conversation resolution; admin tunduk aturan | Bukan audit penetrasi menyeluruh |
| Akses | Tidak ada kolaborator tambahan; token Actions read-only secara default | CLI perangkat luar Work belum dipasang/diuji |

## Satu otak canonical; Management dihapus

- Tiga workflow Management/team, enam script, workplan dan roadmap spesialis
  dihapus; hook pemanggilnya di Body CI juga dihapus. Sejarah tersedia di Git.
- `UnifiedKatarinaBrain` menjadi satu pintu masuk observer. Persepsi pasar,
  pembelajaran kognitif, recall Neuro-Link dan sintesis riset entry/exit merupakan
  kemampuan di instance yang sama, tanpa worker atau scheduler kedua.
- Fast/Deep menggunakan MemoryStore dan checkpoint yang sama. Pembacaan causal
  mempertahankan waktu pertama informasi tersedia, checksum, provenance dan
  penolakan duplikasi/tampering. Outcome quote hanya OBSERVED, bukan profit broker.
- Rollback Owner dan knowledge window yang terpotong menahan sampling virtual.
  Parameter D1–D6 yang masih membutuhkan validasi tidak diisi sembarangan.
- Cloud Hands, autentikasi Owner, validasi broker dan VPS tetap belum selesai.
  Rekayasa satu otak bukan klaim seluruh grand desain sudah siap produksi.

Diagram dan kontrak ada di [arsitektur unified](architecture/KATARINA_UNIFIED_V1_SYNC.md).

## Integrasi branch sebelumnya

[PR #85](https://github.com/alfaauliau-katarinaAI/Katarina-AI/pull/85)
menyatukan riwayat 34 branch setelah verifikasi patch-id atau blob file identik.
[PR #86](https://github.com/alfaauliau-katarinaAI/Katarina-AI/pull/86)
mengintegrasikan Neuro-Link, shadow paper/replay dan penelitian portfolio offline.
Pembacaan memori tetap memeriksa checksum dan menolak payload yang berubah.

Perubahan lama yang sudah ditingkatkan dipertahankan dalam bentuk main terbaru.
Ekstraksi website tidak diterapkan sebagai penghapusan 799 file AI: instruksinya
masuk ke `docs/deployment/STANDALONE_WEBSITE_EXTRACTION.md`.
Varian portfolio historis berada di
`src/katarina/research/experimental_strategy_evidence_portfolio.py`, tanpa
registrasi runtime atau perubahan strategi produksi.

Bukti per branch: [34 branch setara](operations/BRANCH_CONSOLIDATION_20261015.json),
[delapan resolusi unik](operations/BRANCH_UNIQUE_INTEGRATION_20261015.json),
dan [receipt cleanup](operations/BRANCH_CLEANUP_RESULTS_20261015.json).
Seluruh head awal tersimpan sebagai ancestor main; tidak ada force push.

## Bukti CI dan cleanup

- [Body CI PR #85](https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions/runs/38762804497).
- [Body CI PR #86](https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions/runs/38763776156).
- [Body CI main integrasi](https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions/runs/38764010009).

- [Cleanup execute 1](https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions/runs/38763507369): 10 branch dihapus; 33 total branch tersisa.
- [Cleanup execute 2](https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions/runs/38764266063): 10 branch dihapus; 23 total branch tersisa.
- [Cleanup execute 3](https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions/runs/38764494806): 10 branch dihapus; 13 total branch tersisa.
- [Cleanup execute 4](https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions/runs/38764768540): 10 branch dihapus; 3 total branch tersisa.
- [Cleanup execute 5](https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions/runs/38764950294): 2 branch dihapus; 1 total branch tersisa.
- [Dry-run penutup](https://github.com/alfaauliau-katarinaAI/Katarina-AI/actions/runs/38765089798): 0 kandidat, 0 penghapusan.

Setiap eksekusi mengecek ulang SHA branch, strict ancestry, protection dan PR aktif.
Daftar branch dicocokkan setelah setiap batch. Main dipertahankan karena default
branch dilindungi. Seluruh 42 kandidat awal telah diselesaikan; tidak ada branch
unik yang ditinggalkan atau dihapus sebelum integrasi dan CI.

## Prioritas berikutnya

1. Verifikasi checkout, fingerprint modul, lokasi memori dan proses VPS secara
   read-only sebelum menyatakan otak yang berjalan di VPS sinkron.
2. Autentikasi CLI pada perangkat kerja tujuan bila dibutuhkan, sesuai
   [panduan akses](operations/GITHUB_ACCESS.md).
3. Evaluasi bukti broker prospektif secara terpisah; repository rapi dan CI hijau
   tidak mengaktifkan live trading.

Gunakan [CHANGELOG](../CHANGELOG.md) dan commit SHA untuk menelusuri perubahan.
