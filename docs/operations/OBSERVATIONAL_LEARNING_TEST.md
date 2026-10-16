# Pengujian belajar harga dan berita

Owner meminta pengujian riset terbuka pada 16 Oktober 2026. Riset observasional
tidak lagi menunggu sinyal entry atau outcome trade: setiap pass otak yang sama
menyimpan quote broker yang sudah diterima, termasuk ketika semua aksi WAIT.
Tidak ada observer, scheduler atau koneksi model baru.

`latest.json.observational_associations` memuat jumlah sampel, korelasi log-return
antar-instrumen, dan hubungan jumlah artikel yang baru diterima dengan besar
return. Snapshot ringkas juga masuk MemoryStore bersama sebagai
`observational_associations_v1`. Ini pencatatan/penghitungan deterministik,
bukan penalaran model bahasa yang belum dikonfigurasi.

Hanya bucket UTC lima menit yang sudah selesai dipakai; return melewati bucket
yang hilang tidak dihitung. Pasangan instrumen memakai bucket yang sama, tetapi
tick terakhir dalam bucket tidak harus serempak. Minimum 20 pasangan digunakan
sebelum koefisien Pearson ditampilkan. Sedikit sampel atau fitur tanpa variasi
ditampilkan apa adanya, tanpa membuat korelasi palsu. Setidaknya sekitar 100 menit
data kontinu dibutuhkan dari awal pencatatan; pemanasan bucket dapat menambah waktu.

Berita dihitung menurut waktu pengambilan lokal yang tersimpan dan checksum body,
bukan menganggap artikel sudah diketahui pada tanggal publikasinya. Waktu
publikasi yang lebih baru daripada body yang tersimpan ditolak. Perubahan
timestamp RSS tidak lagi memberi label tanggal baru kepada body lama.

Tidak ada klaim kausalitas, signifikansi statistik, sentimen tervalidasi,
profitabilitas atau promosi strategi. Paparan berita bersama, autokorelasi dan
banyaknya perbandingan belum dikendalikan. Kalender/Fed/ECB/BoE serta body CNBC
tetap dikumpulkan lewat fetcher yang sudah ada; belum merupakan pencarian web
umum yang diarahkan model. Penambahan sumber memerlukan konfigurasi dan pengujian.

Anggaran baca 2000 titik per instrumen, 17 instrumen, timeout/ukuran unduhan dan
validasi waktu/checksum tetap berlaku untuk menjaga VPS. Ini batas teknis yang
diungkapkan, bukan mode tanpa batas. Akun, privasi, Risk Governor dan LIVE OFF
tidak diubah. Pengujian riset ini tidak membatalkan penundaan pembuktian strategi.
