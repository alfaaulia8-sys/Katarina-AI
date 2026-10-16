# Progres yang dapat diselesaikan tanpa model dan TLS

16 Oktober 2026. Patokan tetap satu `UnifiedKatarinaBrain`, satu memori Fast/Deep,
Risk Governor independen dan LIVE OFF. Alat di bawah tidak memasang model,
membuka firewall, menyalakan server atau mengganti proses observer aktif.

## Pemeriksaan konfigurasi tanpa jaringan

```sh
python scripts/pc/check_dialog_readiness.py --model-config PRIVATE_MODEL_CONFIG
python scripts/pc/check_dialog_readiness.py --model-config PRIVATE_MODEL_CONFIG --bind HOST_IP --cert CERT_FILE --key KEY_FILE --access-config PRIVATE_ACCESS_CONFIG
```

Model ID placeholder dan kredensial HTTPS yang belum tersedia menjadi blocker.
Konfigurasi Owner yang dicabut/rusak serta pasangan sertifikat/key yang tidak
dapat dimuat juga memblokir. Output tidak menampilkan URL, model ID, token,
account atau isi sertifikat. Tidak ada provider call, port bind atau perubahan file.
`CONFIGURED_NOT_NETWORK_VERIFIED` berarti konfigurasi lokal dapat diperiksa;
bukan bukti masa berlaku/hostname sertifikat, trust HP, firewall atau DNS.
Tanpa `--access-config`, token Owner dibaca dari `KATARINA_OWNER_TOKEN`.

## Pengujian tugas Indonesia yang siap dijalankan

```sh
python scripts/pc/evaluate_dialog_model.py
python scripts/pc/evaluate_dialog_model.py --run --model-config PRIVATE_MODEL_CONFIG --output-dir PRIVATE_NEW_EVALUATION_FOLDER
```

Perintah pertama hanya mencetak rencana `PREPARED_NOT_RUN`, tanpa panggilan model.
Perintah kedua memerlukan konfigurasi nyata dan dapat memakai kuota provider.
Delapan tugas menguji aritmetika, fakta file buatan dengan provenance, penyimpanan
kode sesi dan recall setelah restart, masing-masing pada Fast dan Deep eksplisit.
Angka/kode dibuat saat trial, bukan jawaban tetap yang dibundel. Setiap turn tetap
dibatasi empat panggilan model: maksimal 32 panggilan untuk satu trial.

Setiap trial membuat folder baru dan dua state uji terisolasi; brain Fast ditutup
sebelum brain Deep dibuat. Ini acceptance foreground tanpa broker, bukan worker
produksi tambahan. Jangan memakai database/memori observer sebagai input. Model
hanya memperoleh fakta buatan dan workspace trial, tanpa private source grants.
State lokal memuat prompt/jawaban uji; simpan privat. Ringkasan hanya memuat skor,
latensi turn, mode dan jumlah panggilan, tanpa isi jawaban. Latensi mencakup kerja
lokal; penggunaan token dan biaya tetap `null` sampai ada bukti provider.

Kelulusan exact-match tidak membuktikan kecerdasan umum, kualitas strategi atau
tingkat halusinasi. Manusia tetap perlu menilai tugas terbuka, penolakan instruksi
berbahaya, kesalahan faktual, biaya, latensi dan kualitas bahasa Indonesia.
Tidak ada promosi strategi atau aktivasi trading dari skor ini.

## Bagian yang masih belum bisa ditutup

| Gerbang | Yang masih diperlukan | Bukti penyelesaian |
|---|---|---|
| Dialog model nyata | Endpoint Fast/Deep, ID model terpasang, kredensial bila perlu | Trial nyata dan review jawaban, bukan fixture CI |
| Akses HP | Host/domain tujuan, sertifikat dan key valid, DNS/jaringan yang diizinkan | Login Owner lewat HTTPS di HP dan trust sertifikat |
| Owner dan observer satu instance | Konfigurasi model/access siap, jendela pergantian proses terkontrol | Dialog dan observasi memakai lock/memori instance yang sama |
| Audit runtime mendalam | Fingerprint modul yang dimuat dan pemeriksaan memori yang aman | Bukti source proses dan integritas, bukan sekadar checkout Git |
| Alpha/forward strategi | Dataset holdout, biaya broker dan waktu observasi prospektif | Evaluasi independen; jumlah siklus bukan jumlah trade independen |
| Eksekusi broker demo | Lingkup pengujian dan persetujuan khusus eksekusi, gerbang yang sesuai | Fill/cancel/reprice/partial/trailing dan rekonsiliasi |

Jalur WAIT/ACK dan runtime baca-saja telah memiliki bukti target host. Pemeriksa
runtime pada commit `ff5968a3c8a8d0fbd10cbde0972ab805ecc35936` lulus pada
16 Oktober 18.27 WIB: 407/407 siklus, 3 instrumen, tanpa blocker. PR #100 sudah
digabung. Itu tidak membuktikan source baru sudah dimuat oleh proses yang lama.
