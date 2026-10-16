# Akses status Owner pada otak yang sedang mengamati

`--owner-status-ui` menambahkan permukaan HTTP terautentikasi pada proses
`--continuous` yang sama. Model tidak diperlukan untuk memeriksa status.
Ini bukan model pengganti: dialog tanpa konfigurasi ditolak sebagai
`BLOCKED_MODEL_NOT_CONFIGURED` dan tidak ditulis sebagai percakapan AI.

```sh
python scripts/ai/run_contextual_market_observer.py --continuous --connection-config PRIVATE_CONNECTION_CONFIG --state-dir EXISTING_OBSERVER_STATE --owner-status-ui --owner-access-config PRIVATE_ACCESS_POLICY
```

Hentikan proses lama secara tertib sebelum menjalankan perintah ini. Gunakan
state dan binding akun yang sama; jangan memulai `run_assistant`/`ui` terpisah
di state lain untuk menggantikan permukaan ini. Jalankan pada sesi Windows
Owner yang memiliki terminal MT5. Lock tetap melarang observer ganda.

Buka `http://127.0.0.1:8765` pada PC host, masukkan token Owner yang sudah
diterbitkan di host, kemudian tekan **Periksa status Katarina**. Token tidak
ditaruh dalam URL, cookie atau localStorage. `POST /status` memerlukan bearer
yang sama dengan `/turn` dan body tepat `{}`. Output hanya memuat hasil
pemeriksa snapshot baca-saja, ketersediaan dialog dan gerbang DISABLED.
Analyst juga boleh membaca status yang sudah direduksi; pencabutan akses
diperiksa pada setiap permintaan. Data akun, isi memori dan kredensial tidak
menjadi bagian respons status.

Permintaan dijalankan serial pada idle loop observer. Tidak ada thread/server
worker tambahan. Saat pass sensor aktif, HTTP menunggu pass selesai; ini belum
menjamin batas latensi interaksi. Pemeriksaan status tidak memperbarui heartbeat
atau menyulap data pasar usang menjadi segar. Snapshot BLOCKED ditampilkan apa adanya.

Tambahkan `--owner-model-config PRIVATE_MODEL_CONFIG` bila endpoint yang
diizinkan sudah terpasang. Dialog lalu memakai instance dan MemoryStore yang
sama. Restart terkontrol diperlukan untuk mengganti konfigurasi permukaan.

Untuk HP, gunakan bind jaringan yang diizinkan, `--owner-cert` dan `--owner-key`
yang valid. HTTP non-loopback tetap ditolak; nama host, DNS, firewall, masa
berlaku dan trust sertifikat pada HP masih perlu bukti nyata. Loopback PC
bukan bukti akses dari HP. Tidak ada port publik baru yang dibuka alat ini.

Rollback: hentikan proses baru secara tertib lalu kembalikan argumen observer
sebelumnya dengan state/binding yang sama. Database tidak dihapus atau dimigrasi.
Pembuktian strategi, holdout, alpha dan forward test ditunda atas instruksi Owner;
perubahan ini hanya integrasi teknis, LIVE OFF.
