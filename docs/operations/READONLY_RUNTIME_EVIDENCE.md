# Pemeriksaan runtime sesuai diagram satu otak

Pemeriksaan ini membaca dua JSON publikasi observer. Tidak membuka database,
mengambil lock, menyambungkan broker, atau memulai observer kedua.

```sh
python scripts/pc/check_runtime_evidence.py --state-dir PATH_TO_EXISTING_OBSERVER_STATE
```

Kode keluar 0 berarti `PASS_READONLY_SNAPSHOT_ONLY`; kode 2 berarti `BLOCKED`.
Default umur maksimum heartbeat, keberhasilan, observasi dan tick pasar adalah
180 detik. Batas dapat ditentukan eksplisit melalui `--max-age-seconds` (30–3600).
Tick masa depan, heartbeat tanpa observasi segar, data sebagian, observer berhenti,
receipt kurang/ganda, counter hilang dan izin live yang tidak eksplisit OFF
memblokir hasil. Pasar tutup dapat menghasilkan BLOCKED karena tick usang;
ini bukan alasan memperlakukan heartbeat sebagai data pasar baru.

Output hanya memuat counter, kode blocker dan batas bukti; isi snapshot, account,
endpoint, token dan database tidak dicetak. Snapshot ditulis atomik oleh observer
tetapi dua file tidak merupakan satu transaksi. Ketidakcocokan sesaat dapat
menghasilkan BLOCKED; ulangi pemeriksaan sesudah satu siklus normal sebelum
menyimpulkan kegagalan permanen. Jangan memulai worker pengganti dari hasil ini.

Receipt merupakan bukti ACK jalur WAIT yang diperiksa adapter saat pengamatan,
bukan fill broker. Pemeriksaan hanya memeriksa bentuk/hash unik pada snapshot,
tidak mengulang verifikasi pesan asli atau membuktikan bahwa host bebas manipulasi.
Snapshot juga bukan bukti independen identitas proses, checksum memori, fingerprint
modul Python yang sudah dimuat atau kecocokan commit proses yang sedang berjalan.

## Bukti host yang diamati 16 Oktober 2026

Pemeriksaan baca-saja sekitar 18.19 WIB menemukan checkout aplikasi pada commit
`639264644cce61a7b44393bd1ff82b9d7747d43e`, observer tunggal yang teridentifikasi
melalui command line, dan terminal MT5 aktif. Snapshot 18.18.52 WIB mencatat
399/399 siklus, 3 instrumen, 0 kegagalan beruntun, 0 order dan live OFF.
Pembacaan berikutnya pada sesi yang sama menemukan tiga receipt
`ACKNOWLEDGED_LIVE_OFF`. Data akun, isi memori dan kredensial tidak disalin.

Ini bukti historis terbatas, bukan status terus-menerus atau pengujian perintah
baru di host. Dokumen status lama yang menyatakan VPS belum diperiksa perlu
dibaca bersama batas ini: checkout/proses/snapshot telah dilihat, fingerprint
modul yang dimuat dan audit memori belum dibuktikan.

## Gerbang berikutnya dalam diagram

1. Jalankan pemeriksaan baru pada host setelah CI commit ini lulus; simpan SHA,
   waktu, exit code dan output ringkas. Pemeriksaan tidak memerlukan restart.
2. Konfigurasikan endpoint model yang diizinkan sebelum menguji dialog Fast/Deep
   dengan tugas Indonesia yang belum dilihat model. Respons koneksi saja tidak
   membuktikan kualitas, biaya atau latensi.
3. Validasi autentikasi dan TLS pada jaringan HP nyata untuk permukaan Owner pada
   instance otak yang sama. Jangan memulai UI dengan lock/state lain sebagai jalan pintas.
4. Validasi strategi holdout dan forward prospektif secara terpisah. Uji eksekusi
   broker memerlukan lingkup dan izin tersendiri; gerbang pengiriman tetap OFF.
