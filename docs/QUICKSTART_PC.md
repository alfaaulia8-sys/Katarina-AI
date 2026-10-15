# Uji Katarina langsung di komputer

**Development preview; semua peluncur ini LIVE OFF.** Tidak perlu VPS, akses admin,
GitHub login, Git, terminal MT5, atau akun broker untuk uji sintetis. Python 3.12
64-bit dan internet pemasangan dependensi diperlukan. Uji sesudah pemasangan dapat
offline. Tidak ada program yang dipasang sebagai startup/service/background.

## Windows: dua langkah

1. Unduh source dari `main` atau paket artifact `Katarina-PC-Test` pada workflow
   **KATARINA Body CI** yang sukses. Ekstrak ZIP seluruhnya ke folder yang dapat
   ditulis, misalnya Documents/Katarina. Jangan jalankan dari dalam ZIP.
2. Pasang Python 3.12 64-bit jika belum ada, lalu klik **SETUP_KATARINA.bat** sekali.
   Tunggu `SETUP_OK`. Klik **START_KATARINA.bat** untuk uji.

Setup memilih environment privat tervalidasi di `.katarina-envs` dan memasang dependensi ke sana,
bukan ke Python global. Tidak memasang Git/winget, tidak mengambil credential,
tidak mengubah izin MT5, tidak membuat supervisor, dan tidak mengunggah laporan.
START_KATARINA lama yang membuka supervisor VPS telah diganti menjadi uji PC.
Script supervisor historis tidak dijalankan oleh peluncur baru.

Hasil yang benar: **PASS_SYNTHETIC_PC_ONLY**. Buka `latest-pc-test.html` pada lokasi
yang ditampilkan konsol. JSON tersedia di sebelahnya. Uji mencakup tiga sensor
harga buatan melalui pipeline otak sebenarnya, penyimpanan memori, dan pembukaan
ulang checkpoint dua kali. Ini bukan hasil backtest, profit, atau verifikasi broker.

## Linux/macOS dan pilihan command line

```sh
python3.12 katarina_pc.py setup
python3.12 katarina_pc.py doctor
python3.12 katarina_pc.py test
```

Di Windows gunakan `py -3.12` sebagai pengganti `python3.12`. Folder source boleh
berisi spasi; perintah memakai path relatif terhadap script, bukan direktori kerja.
`--state-dir` memilih lokasi laporan/state. Jika tidak diisi, gunakan
`KATARINA_STATE_DIR`, kemudian lokasi bawaan OS pada panduan host portabel.

## Pembacaan MT5 nyata, tetap tanpa order

Ini langkah terpisah setelah uji sintetis lulus:

1. Pada Windows 64-bit, jalankan `py -3.12 katarina_pc.py setup --mt5`.
2. Siapkan terminal MT5 dan login akun yang memang diizinkan. **Matikan Algo Trading**.
   Katarina akan menolak terminal yang masih mengizinkan trading; tidak mematikannya
   diam-diam atau mengganti akun.
3. Buat file koneksi privat berdasarkan `config/connection_readonly.example.json`.
   Isi login/server yang benar dan terminal_path jika diperlukan. Pilih priority
   `["local"]` bila belum mempunyai sensor cloud. Jangan gunakan akun contoh.
4. Jalankan:

```sh
py -3.12 katarina_pc.py observe --connection-config C:/private/katarina-connections.json
```

Tanpa MT5 lokal, komputer Linux/macOS dapat memakai sensor cloud yang sudah dipasang
sesuai kontrak koneksi otomatis. Setup standar tidak memasang adapter native MT5.
Tidak perlu maupun boleh memasukkan password akun ke source repository.

Uji nyata hanya lulus dengan **PASS_READONLY_OBSERVATION_ONLY**, akun terikat,
dan pembacaan sensor tanpa error. Fallback offline **tidak** dianggap lulus uji
broker. Pasar tutup/data basi, koneksi tidak valid, atau sensor gagal dapat membuat
hasil BLOCKED; periksa konfigurasi/ketersediaan data dan jalankan lagi.
Tidak menguji order, recovery posisi live, hasil strategi atau profitabilitas.

## Laporan, state, dan pemulihan

- Tiap uji sintetis memakai direktori baru `pc-tests/<id>`; tidak mencampurkan harga
  buatan dengan state `readonly-observer` untuk observasi broker.
- Laporan ringkas terbaru menampilkan input, status, hasil pemeriksaan dan alasan
  BLOCKED yang telah disaring; tidak memuat token, alamat server, atau login akun.
- Laporan HTML dapat dibuka di browser tanpa server web. Tidak membuka browser otomatis.
- Simpan seluruh direktori state setelah proses ditutup untuk melanjutkan memori.
  Banyak pengulangan uji demo akan menambah folder; hapus hanya folder demo yang
  tidak dibutuhkan setelah proses berhenti. Tidak ada pembersihan otomatis.
- Jika SETUP_REQUIRED, jalankan setup. Jika Python salah versi, pasang Python 3.12.
  Jika pemasangan gagal, periksa pesan pip, jaringan dan ruang disk, lalu ulangi.
  Jika laporan BLOCKED, jangan menganggap Katarina siap trading.

Paket ZIP hanya source dan manifest checksum `SOURCE_REVISION.json`. Python,
dependensi, MT5, sertifikat, private state dan credential tidak dibundel. Manifest
memberi jejak commit/file, bukan tanda tangan distribusi independen. Untuk bukti
CI terbaru lihat workflow pada commit sumber, bukan hanya nama paket.

## Jika dependensi rusak

START memeriksa environment dan mencoba pengganti yang diuji terlebih dahulu.
Environment lama dan memori tidak dihapus. Lihat
[pemulihan environment](architecture/KATARINA_ENVIRONMENT_RECOVERY.md).
`py -3.12 katarina_pc.py repair-status` melihat status; `repair` mencoba perbaikan
eksplisit. `test --no-auto-repair` menonaktifkan pemasangan pengganti otomatis.
Python 3.12 tetap perlu disiapkan pemilik; live selalu OFF.
