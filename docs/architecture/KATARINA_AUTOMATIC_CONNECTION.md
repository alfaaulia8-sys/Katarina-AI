# Koneksi otomatis, akun terikat, tetap baca-saja

16 Oktober 2026 WIB. Katarina memilih jalur menurut konfigurasi pemasangan:
local → cloud → riset offline. Urutan dapat dibalik. Hanya satu adapter digunakan
per pass; tidak ada scan jaringan atau pemilihan akun broker sembarang.

## Konfigurasi sekali, pemilihan setiap peluncuran

Salin `config/connection_readonly.example.json` ke lokasi privat di luar git.
Isi login dan nama server akun yang diizinkan. Jika ada beberapa terminal, isi
`terminal_path` dengan executable terminal yang benar. Hapus `cloud_url` atau
atur null bila belum memiliki sensor remote. Contoh endpoint tidak aktif.
Simpan token acak minimal 32 karakter ASCII tanpa spasi di environment yang
namanya ditunjuk `cloud_token_env`; jangan taruh token/password broker di JSON.

```sh
python scripts/ai/run_contextual_market_observer.py --connection-config /private/connections.json --no-fetch
```

Bisa juga menetapkan `KATARINA_CONNECTION_CONFIG` ke file tersebut, lalu memakai
perintah biasa. Explicit `--offline-research` dan `--doctor` tidak membuka koneksi.
Tanpa konfigurasi identitas, launcher otomatis menjalankan riset lokal saja.
JSON tidak valid memblokir peluncuran; tidak diabaikan diam-diam.

Adapter lokal memeriksa koneksi terminal, trade_allowed=False, login dan server
sebelum pembacaan. Native MT5 diimpor secara lazy hanya pada jalur lokal terpilih.
Tidak ada pemanggilan login, pemasangan EA, perubahan izin trading, order_send,
atau order_check. `symbol_select(True)` mengikuti observasi lama untuk Market Watch;
tidak membuka posisi. Broker credential/terminal harus disiapkan pemilik host.

## Sensor cloud HTTPS v1

`KATARINA_READONLY_SENSOR_V1` adalah adapter sensor baru, **bukan** penggantian
protokol KAT1 yang dibekukan, bukan gateway eksekusi, dan bukan bukti Cloud Hands
produksi sudah terpasang. Host MT5 dapat menjalankan sidecar eksplisit:

```sh
python scripts/ai/run_readonly_sensor_bridge.py --connection-config /private/connections.json --cert /private/sensor-cert.pem --key /private/sensor-key.pem --bind 127.0.0.1
```

Untuk lintas host, operator perlu memilih bind/reachability/firewall yang tepat,
sertifikat dengan SAN sesuai hostname dan chain yang dipercaya client, serta token
yang sama di kedua environment. Default bind loopback tidak terekspos ke internet.
Private key/sertifikat server dan token tidak dihasilkan, diunggah, atau disalin
otomatis. Trust store standar Python dipakai; tidak ada verify=False atau HTTP.
Server ini sensor satu pemilik proses, bukan deployment terukur/HA. Daemon hanya
berjalan jika sidecar diluncurkan eksplisit; otak sendiri tetap satu pass.

Setiap request memakai bearer melalui TLS, ID request acak, waktu maksimum selisih
30 detik, dan ID sesi server. Client menolak redirect, proxy environment otomatis,
sertifikat tidak dipercaya, nonce salah, protokol/sesi berubah, error dan respons
>4 MiB. Timeout per request 5 detik. Sinkronisasi jam diperlukan. Server memeriksa
binding akun/izin setiap operasi dan hanya mengizinkan daftar pembacaan terbatas.
Window data/bar dibatasi; permintaan order dan perubahan akun tidak tersedia.
Respons tidak membuktikan kebenaran broker secara independen: host sensor dan
pemegang token tetap bagian trust boundary. Jangan memaparkan sensor ke publik
sebelum konfigurasi akses dan pengamanan host diverifikasi.

## Putus koneksi dan pemulihan

Saat kesalahan koneksi terdeteksi, adapter sesi dianggap gagal. Otak menutup
resource dan lock; pemilihan mengulangi **seluruh pass** dengan binding/sesi baru,
bukan melanjutkan respons lama. Maksimum 1..3 percobaan per jalur (default 2).
Sesudah semua jalur gagal, satu siklus riset lokal dijalankan dan alasan generik
tercatat tanpa login, endpoint, atau token. Error integritas/data/aplikasi tidak
dianggap koneksi gagal dan tidak disembunyikan sebagai sukses offline.

Tidak ada retry order, antrean eksekusi, jaminan rekonsiliasi posisi live, worker
reconnect background, atau otorisasi trading. Catatan bukti valid yang sempat
tersimpan tetap tunduk validasi/deduplikasi lama; tidak ada penghapusan state.
Hasil berisi route/attempt dan status live=False. Pemulihan berikutnya otomatis
pada peluncuran berikutnya; tidak ada scheduler baru yang dipasang.

## Bukti penerimaan

Tes menguji fallback lokal/cloud/offline, akun/terminal aktif ditolak, akun berubah,
pass diulang utuh, error aplikasi tidak disamarkan, protokol/nonce/clock/session,
wire datetime/NumPy, pipeline observer sebenarnya melalui sensor sintetis, serta
HTTPS loopback dengan sertifikat sementara (trust dan token salah ditolak).
CI lintas OS menjalankan tes portable dan koneksi. Jika openssl tidak tersedia,
tes HTTPS bersertifikat sementara ditandai skip secara eksplisit.
Koneksi MT5/Cloud riil belum diverifikasi, tidak ada endpoint/akun nyata dipilih,
Risk Governor tetap independen dan live tetap OFF.
