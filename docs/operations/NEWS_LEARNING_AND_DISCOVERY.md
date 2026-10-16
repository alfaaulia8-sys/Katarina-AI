# Berita, reaksi pasar dan pencarian kandidat

Perintah Owner 16 Oktober 2026 mengizinkan riset berita dan kandidat strategi.
LIVE OFF, satu observer dan state/memori bersama tetap berlaku. Ini bukan
aktivasi pencarian web/model tanpa konfigurasi.

Tambahkan `--extended-news-research` pada observer continuous yang sudah ada.
Kolektor tambahan bergilir mengambil rilis Bank of Canada dan RBA; collector
Fed/ECB/BoE/kalender/CNBC lama tetap berjalan. Registry metadata sumber lain
tidak otomatis menjadi konektor jaringan. Satu sumber tambahan diperiksa per
pass, dengan cache/backoff 30 menit, host HTTPS tetap, tanpa redirect, 8 detik
per permintaan dan 600 KB maksimum. Isi luar adalah data, bukan instruksi.

Body minimal 95 kata disimpan bersama hash, URL, waktu publikasi dan waktu
pengambilan pertama. Cache body CNBC dan Fed/ECB/BoE yang sudah ada ikut
diimpor dengan timestamp pengambilan aslinya, tanpa mengisinya mundur ke 2025.
Ringkasan ekstraktif maksimum 120 kata masuk MemoryStore
sebagai `research_news_body_v1`. Ini bukan kesimpulan semantik LLM, sentimen
tervalidasi atau izin makro/trading. Revisi body pada URL lama belum diarsipkan
sebagai vintage baru; jangan menganggap tabel ini sebagai arsip historis lengkap.

`latest.json.news_market_event_study` mengukur return mid setelah pengambilan
body pada horizon 15/60 menit. Quote masuk/keluar harus benar-benar teramati
dalam toleransi 180 detik; data hilang dan jendela belum matang dicatat, tidak
diisi perkiraan. Agregat dengan <20 event ditandai INSUFFICIENT_EVENTS. Tidak
ada pembuktian sebab-akibat, event independen, biaya transaksi atau strategi
dari angka tersebut. Event yang tumpang tindih belum dikoreksi.

## Pencarian aturan pada backtest harga asli

`scripts/research/discover_broker_h1.py --output-dir PRIVATE_NEW_DIRECTORY`
mengambil H1 Januari 2025 sampai saat pengujian pada XAUUSD, EURUSD dan USDJPY.
Mesin discovery yang ada menelusuri BUY/SELL, kombinasi fitur, SL/TP dan horizon
dengan seed tetap 42, populasi 24 dan 8 generasi (maksimal 192 trial per simbol).
Seleksi memakai 60% train dan 20% validation; tiga shortlist baru dinilai pada
20% terakhir. Seluruh sejarah sudah pernah diperiksa proyek, sehingga bukan
pristine holdout atau bukti forward independen. Spread ATR dan biaya R masih
asumsi model; input bid OHLC bukan bid/ask fill broker.

Output lengkap menyimpan genom, skor train/validation/diagnostic holdout,
hash dataset, coverage bulanan dan batas bukti. Tidak ada perubahan strategi
produksi, source rewrite oleh model, order atau promosi otomatis. Discovery ini
berbasis harga: `news_features_used=false` sampai arsip berita yang tersedia
pada waktu historis benar-benar ada dan lolos audit vintage/UTC.

Menyimpulkan berita historis dari artikel yang baru diambil sekarang akan
membocorkan masa depan. Integrasi berita ke backtest 2025–2026 masih memerlukan
arsip point-in-time, clock broker/DST yang direkonsiliasi dan validasi biaya.
Pencarian web bebas serta interpretasi LLM tetap membutuhkan model/provider
dan kredensial yang belum dipasang. Tidak ada janji strategi profitable.
