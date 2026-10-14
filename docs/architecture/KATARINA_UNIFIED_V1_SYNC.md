# Katarina V1 — satu pohon kode, satu jalur penelitian

## Sasaran timeline Owner (14 Oktober 2026)

1. **Hidupkan secara aman / satukan fondasi**: Core Orchestrator, Management, data broker, modal, Risk Governor, recovery dan unified brain tetap satu codebase. Tidak membuat EA atau otak kedua.
2. **Stabilkan dan sinkronkan**: satu *pinned* Git commit untuk kandidat integrasi dan isolated worktree VPS; jalur `github-main` yang punya perubahan Owner **tidak ditimpa**.
3. **Belajar dan bereksperimen**: observer tunggal mengalirkan hasil shadow quote yang telah selesai ke `self_evolution_lab`, kemudian mengubah hanya ambang pemilihan eksperimen berikutnya per symbol/metode/BUY/SELL/regime.
4. **Buktikan hasil**: data broker per-deal dan floating P/L asli, server trading-day, uji metode BUY/SELL terpisah, biaya trading aktual, pengujian prospektif forward dan demo. Jika hasil negatif, WAIT; jangan klaim profit.
5. **Rilis bertahap**: only with independent QA, human approval, and original hard Risk Governor. Trading live tidak otomatis diloloskan meski software build lulus.

## Profil terintegrasi saat ini

`config/katarina_unified_v1.json` adalah satu *deployment/acceptance profile* yang menunjuk ke **komponen lama yang sudah ada**, tidak menggantikan orchestrator atau menambah worker. Perintah:

```powershell
$env:PYTHONPATH = "src;."
py -3 -B scripts/ai/verify_unified_katarina.py
```

Perintah ini hanya memeriksa bahwa semua modul inti dapat diimpor, batas risiko final masih benar, dan brain/shadow bisa membaca SQLite. Tidak memanggil `mt5.initialize()`, tidak mengirim order, tidak memodifikasi database maupun menjadwalkan proses. Dengan parameter `--shadow-db`, SQLite lama dibuka **mode read-only**; ini bukan kelulusan live.

**Ditangguhkan sementara** dalam profil: external-model coding workers, self-rewrite produksi, broker-provenance yang belum terverifikasi, server-clock yang belum terverifikasi, migrasi capital state otomatis, scheduler yang telah dibatalkan Owner, dan live execution. Kode/data lama tidak dihapus demi mencegah kehilangan audit trail. Penangguhan itu **tidak boleh menghapus fail-closed gate, mengubah Risk Governor atau menurunkan otorisasi live**.

### Konsistensi modal dan risiko

- Profit Lock = 25% dari realized balance saat milestone berlipat; cadangan tetap *logical reserve*, bukan dana yang sudah ditarik.
- 5% batas maksimum tiap entry, 8% maksimum total open risk lintas posisi Owner/Katarina.
- DD 10–23% caution; 23–35% hanya recovery yang memenuhi bukti; DD >=35% akibat Katarina/unknown → emergency lock. Owner-cause exception hanya dengan atribusi broker lengkap dan pemeriksaan risiko independen.
- Posisi manual Owner tak boleh dimodifikasi tanpa izin.
- Semua fitur produksi yang belum lolos tetap dimatikan; jangan mengubahnya menjadi mode live hanya untuk menyatakan proyek 'selesai'.

### Aturan sinkronisasi aman

1. Jalankan semua pengujian CI dan Management acceptance terhadap SHA yang sama.
2. Fetch SHA yang sudah diperiksa ke **worktree VPS terpisah**, jangan `reset --hard`, `clean`, atau `pull` pada `github-main` yang berisi perubahan lokal Owner.
3. Pastikan `git rev-parse HEAD` dan `git status --porcelain` dari worktree tersebut identik dengan SHA GitHub dan tidak ada perubahan lokal.
4. Jalankan checker read-only di worktree itu, lalu pastikan task terjadwal lama tetap Disabled, RAM cukup, dan MT5 tidak dinyalakan.
5. Hanya satukan perubahan ke `main` setelah seluruh pemeriksaan teknik, konflik dan persetujuan integrasi aman. Rilis live **terpisah** dan tetap blocked sampai data/forward siap.

**Keberhasilan integrasi software bukan pembuktian edge atau aktivasi trading.**
