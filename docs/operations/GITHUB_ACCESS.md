# Akses GitHub di luar ChatGPT Work

Repository: `alfaauliau-katarinaAI/Katarina-AI`. Pemilik: `alfaauliau-katarinaAI`.

## Status yang benar-benar tersedia

| Jalur | Status snapshot 15 Oktober 2026 | Batas |
|---|---|---|
| Koneksi GitHub akun pemilik di Work | Membaca/menulis source dan PR telah terbukti pada PR #81–83 | Katalog tool tidak menyediakan seluruh endpoint GitHub; admin/API tertentu masih terbatas |
| Browser GitHub di Work | Sesi pemilik sudah memverifikasi perubahan setting | Sesi browser dapat berakhir atau meminta verifikasi ulang |
| Git/CLI checkout kerja sesi ini | Fetch publik berhasil | Push HTTPS tidak terautentikasi; GitHub CLI belum terpasang |
| CLI pada VPS/komputer di luar Work | Belum diverifikasi/diaktifkan oleh pekerjaan ini | Membutuhkan login pada perangkat itu; izin chat tidak menghasilkan kredensial perangkat |
| Agent yang bekerja saat chat berhenti | Tidak dibuat atau diaktifkan | Memerlukan runtime, pemicu, kredensial dan batas tindakan yang terpisah |

Tidak ada token yang disalin dari konektor atau cookie browser. Tidak ada
kredensial permanen, app baru, deploy key, scope admin tambahan, atau bypass
proteksi yang dibuat otomatis oleh dokumen ini.

## Menyiapkan perangkat tujuan

1. Pasang Git dan GitHub CLI dari distribusi resmi GitHub pada perangkat kerja.
   Gunakan credential manager/keyring OS bila tersedia. Windows Server lama harus
   diperiksa kompatibilitasnya sebelum instalasi; jangan menganggap winget tersedia.
2. Jalankan login interaktif pada perangkat tersebut:

   ```sh
   gh auth login --hostname github.com --git-protocol https --web
   gh auth setup-git --hostname github.com
   gh api user --jq .login
   ```

   Pastikan akun yang dipilih adalah pemilik di atas. GitHub menampilkan izin yang
   diminta dalam flow login. Jangan kirim password, kode login, atau token ke chat.
   Token konektor Work tidak dapat diekspor untuk langkah ini. Penambahan scope atau
   kredensial persisten harus dilakukan melalui persetujuan aman pada perangkat.
3. Clone repository, atau periksa remote dan perubahan lokal sebelum fetch/pull:

   ```sh
   gh repo clone alfaauliau-katarinaAI/Katarina-AI
   cd Katarina-AI
   git remote -v
   git status --short
   git fetch origin main
   git switch main
   git merge --ff-only origin/main
   python scripts/github/check_access.py
   ```

   Berhenti jika checkout memiliki perubahan yang belum disimpan atau merge
   bukan fast-forward. Jangan gunakan reset paksa untuk menutupi perbedaan sumber.
4. Checker hanya memanggil endpoint GET dan menampilkan identitas, role repository,
   serta kemampuan baca. `push/admin=true` bukan bukti token memiliki seluruh scope.
   Checker sengaja menyatakan `write_operations_verified=false`; write baru terbukti
   setelah tindakan yang sah berhasil. Kemampuan mengubah workflow/Actions/settings
   harus diverifikasi per tindakan, tanpa mengubah proteksi main untuk mengujinya.

## Pola kerja setelah autentikasi

Buat branch pekerjaan, commit perubahan, push branch dan buka PR. Tunggu `body` CI,
perbaiki kegagalan, lalu merge lewat aturan main. Gunakan workflow cleanup manual
dengan `execute=false` terlebih dahulu. Penghapusan hanya dilakukan setelah hasil
dry-run direview dan syarat ancestry/proteksi/PR dicek ulang.

Tidak ada prosedur yang memberi orang luar akses edit. Repository publik tetap
bisa dibaca/fork. Akses perangkat lain tidak berarti model/chat akan terus bekerja
di background, dan tidak membuktikan sinkronisasi VPS atau mengizinkan live trading.
