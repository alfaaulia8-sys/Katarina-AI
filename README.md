# KATARINA Web — standalone website source

Folder ini merupakan salinan terpisah dari aset publik website KATARINA AI.

## Cloudflare Pages Free
- Repository: khusus source website (tidak berisi bot/EA/MT5/VPS)
- Framework preset: None
- Build command: kosong
- Build output directory: `website`
- Production branch: `main`
- Cloudflare Pages Functions: `functions/api/hot-news.js`
- API berita: `/api/hot-news`, cache 15 menit selama request tersedia

## Aset
- `website/`: dashboard, halaman riset, HTML/CSS/JS, dan data publik
- `functions/`: Cloudflare Pages Functions untuk RSS publik
- `scripts/update_hot_news.py`: fallback pembaruan data
- `.github/workflows/katarina-hotnews.yml`: fallback pada GitHub Action tiap enam jam

Simpan `CLOUDFLARE_API_TOKEN` dan `CLOUDFLARE_ACCOUNT_ID` hanya di GitHub Actions Secrets, jangan commit ke repository.

Tidak ada broker order, EA privat, atau klaim hasil live trading di paket ini.
