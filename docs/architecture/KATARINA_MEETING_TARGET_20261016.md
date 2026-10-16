# Katarina — acuan rapat dan pelaksanaan 16 Oktober 2026

Owner mengucapkan **deploy all** setelah menyetujui pengembangan bertahap dari
fondasi lama. Perintah ini mengizinkan implementasi, pengujian dan deployment
yang sesuai gerbang proyek. Ini bukan persetujuan metode penelitian tertentu,
perubahan angka risiko, ataupun pengaktifan trading uang nyata.

## Keputusan yang menjadi acuan

| Pokok | Keputusan |
|---|---|
| Sasaran | Masyarakat umum; uji Owner dahulu, lalu kelompok terbatas |
| Tujuan | Buktikan alpha, menjadi asisten analisis dan mencari pertumbuhan akun |
| Otak | Satu UnifiedKatarinaBrain; fungsi internal, bukan banyak pekerja AI |
| Risiko | Risk Governor independen; proteksi, Profit Lock dan recovery lama berlaku |
| Modal | Owner siap kehilangan US$1.000, bukan perintah menghabiskan modal |
| Instrumen | XAUUSD, forex major, US30/US100 dan instrumen likuid yang layak |
| Horizon | Utamakan intraday, lalu scalping; penelitian boleh lebih luas |
| Biaya | Perkiraan ekosistem US$60–100/bulan; Owner menunjang kekurangan sementara |
| Profit | Profit yang direalisasi ke balance; deposit bukan profit |
| Intervensi | Pelajari intervensi yang diizinkan; jangan ubah/tutup posisi manual Owner |
| Data intervensi | Persetujuan pengguna diperlukan; belum mengaktifkan koleksi lintas pengguna |
| Model | Model trading dikembangkan sendiri; model bahasa terbuka dapat menjadi dasar |
| Informasi | V1 sumber gratis, periksa waktu tersedia, mutu, konflik dan provenance |
| Metode baru | Riset → shadow → laporan → persetujuan Owner untuk versi tertentu |
| Adaptasi lama | Hanya dalam rentang yang sudah diuji/disetujui; di luar itu kandidat baru |
| Degradasi | Cari sebab: regime, biaya, kesalahan data/eksekusi atau intervensi; stop/lapor sesuai aturan |
| Penelitian | Kandidat gagal tetap dicatat dan dapat diteliti; jumlah percobaan tidak disembunyikan |
| Bukti | Pisahkan sintetis, historis, shadow dan broker; korelasi bukan bukti independen |
| Laporan | Rekap mingguan; pencatatan dan tindakan proteksi tetap segera saat kejadian |
| Akses | Owner/pihak berizin; kredensial dan kewenangan harus jelas |
| Host | Lokal/cloud/gabungan; satu otak melayani banyak Hands dengan proteksi lokal |
| Otonomi | Kecepatan analisis tidak membolehkan entry tanpa alasan atau melewati veto risiko |

## Tahap source pada perubahan ini

`BrainRuntimeControl.research_review` memakai **MemoryStore yang sama**. Tidak
ada worker, database katalog kedua, scheduler atau otak tambahan. Versi metode
tidak bisa ditimpa. Spesifikasi wajib memuat hipotesis, alasan entry,
invalidation, rencana exit dan digest source. Setiap percobaan menyimpan jenis
bukti, dataset, hasil termasuk kegagalan, biaya, keterbatasan dan digest kebijakan.

Review Owner terikat pada digest **spesifikasi + versi + trial + dataset +
evaluasi + kebijakan**. Perubahan membutuhkan review baru. Tidak ada endpoint
model/browser yang dapat menulis persetujuan ini. Akses CLI lokal adalah batas
kepercayaan sementara, bukan implementasi login multiuser. `ACCEPT_FOR_CONTROLLED_TEST_REVIEW`
berarti diterima untuk langkah review uji terkontrol berikutnya, **bukan metode
aktif**, bukan bukti alpha dan bukan izin mengirim order. Data evaluasi yang
diinput caller selalu berlabel `CALLER_SUPPLIED_UNVERIFIED`; label PASS tidak
menjadi bukti independen. Kandidat sintetis/historis atau hasil FAIL tidak dapat
diterima ke tahap tersebut, tetapi boleh terus diteliti.

Laporan manual memakai interval tujuh hari `[awal, akhir)`, memisahkan jenis
bukti, mencatat kegagalan dan kelompok dataset. Kelompok dataset berbeda belum
tentu independen. Tidak ada laporan harian atau pengiriman pesan otomatis.

MT5 sekarang memberikan kode sebab kegagalan yang statis: paket MT5 tidak ada,
terminal tidak terhubung, izin trading belum OFF, akun/server tidak cocok atau
cloud belum dikonfigurasi. Nilai akun/server/token tidak dicetak. Jalur offline
secara eksplisit menyatakan `receiving_market_data: false`; hasil riset offline
tidak membuktikan MT5 sedang mengirim data. Jika cloud berhasil setelah jalur
lokal gagal, ringkasan kegagalan lokal tetap tersedia.

## Memakai konsol penelitian pada host privat

Jalankan dari root source dengan Python 3.12; state harus sama dengan otak.
Perintah mengambil lock otak yang sama, sehingga tidak berjalan bersamaan dengan
observer/console aktif. Input JSON harus privat, tidak berisi login atau token.

```
python scripts/pc/run_owner_research.py weekly --state-dir PATH
python scripts/pc/run_owner_research.py register --state-dir PATH --input candidate.json
python scripts/pc/run_owner_research.py trial --state-dir PATH --input trial.json
python scripts/pc/run_owner_research.py review --state-dir PATH --input review.json
```

Input `register`: `method`, `version`, `specification` dengan lima kolom di atas.
Input `trial`: `method`, `version`, `trial_id`, `evidence_kind`, `dataset_sha256`,
`evaluation` berisi `result` (PASS/FAIL/INCONCLUSIVE), `costs`, `limitations`,
`policy_sha256`. Jenis bukti: SYNTHETIC/HISTORICAL/PROSPECTIVE_SHADOW/BROKER_DEMO_FORWARD.
Input `review`: `trial_id`, `review_sha256` dari hasil trial, `decision`
(ACCEPT_FOR_CONTROLLED_TEST_REVIEW/REJECT/DEFER), `reason`. Jam pencatatan ditetapkan
konsol, bukan file input. Input tidak dapat menambah parameter risiko atau order.

## Pekerjaan terbuka — jangan dianggap selesai

1. Tetapkan kebijakan penerimaan, jumlah bukti, biaya, drift dan rentang adaptasi
   berdasarkan data; angka ini belum diputuskan dalam rapat.
2. Hubungkan evaluasi dan registry penelitian ke katalog strategi yang benar-benar
   tervalidasi, dengan persetujuan Owner, rollback dan gerbang demo/live terpisah.
3. Latih/evaluasi model trading menggunakan data broker yang dapat diverifikasi;
   belum ada klaim model baru terlatih atau alpha ditemukan.
4. Lengkapi login per peran, isolasi akun, izin/penghapusan data dan pembelajaran
   intervensi. Jangan mengumpulkan data masyarakat sebelum jalur izin siap.
5. Lengkapi dan buktikan proteksi lokal, eksekusi, rekonsiliasi, spread/slippage,
   partial fill, putus koneksi dan pemulihan pada MT5 demo.
6. Verifikasi host/cloud/model nyata, biaya serta akses HP melalui TLS. Tidak ada
   perangkat Desktop Commander terhubung pada awal pekerjaan ini; health VPS UNKNOWN.
7. Jalankan semua gate GitHub pada SHA tepat sebelum verifikasi VPS. Source-only
   ZIP bukan deployment VPS dan bukan runtime Python/model yang telah terpasang.

Tidak ada pengubahan Risk Governor, angka modal/risiko, atau source eksekusi MQL5
dalam tahap ini. Dokumen lama tetap menjadi sumber parameter proteksi; keputusan
rapat terbaru mengatur arah pengembangan dan mengatasi konflik uraian lama.
