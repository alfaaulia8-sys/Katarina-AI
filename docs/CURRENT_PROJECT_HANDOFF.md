# Katarina AI — Current Project Handoff

Updated: **2026-10-15 (Asia/Jakarta)**.

Mulai dari [status proyek terkini](PROJECT_STATUS.md),
[changelog](../CHANGELOG.md), dan
[aturan GitHub-first](operations/GITHUB_FIRST_DEVELOPMENT.md).

Baseline tervalidasi terakhir: `3b43c04f6efc9484b383db135e01ac7d5d3ec611`.
Body CI integrasi dan main lulus. Sepuluh komponen unified terintegrasi dalam verifikasi
offline, tanpa order dan tanpa live execution. GitHub dan checkout kerja cocok;
kesamaan dengan checkout/proses VPS belum diverifikasi.

Repository publik tetap dimiliki akun `alfaauliau-katarinaAI`; main wajib PR dan
CI, dengan larangan force-push/penghapusan. Seluruh 42 branch awal selain main
sudah diselesaikan melalui PR #85/#86 dan guarded cleanup. Hanya main tersisa;
seluruh head lama dipertahankan sebagai ancestor main. Neuro-Link recall dan
riset offline ditambahkan; engine produksi dan Risk Governor tidak diubah.

Akses CLI lintas perangkat: [panduan dan batas autentikasi](operations/GITHUB_ACCESS.md).
Jangan menyalin token aplikasi ChatGPT, cookie browser, atau kredensial ke source,
Actions artifact, issue maupun chat. Jangan menonaktifkan proteksi untuk mengatasi
hambatan akses.

Dokumen terdahulu disimpan sebagai [arsip 10 Oktober](handoff/PROJECT_HANDOFF_20261010.md)
dan [checkpoint sampai 13 Oktober](handoff/KATARINA_START_NEXT_CHAT_20261013.md).
Catatan host lama di dalamnya bukan keadaan VPS saat ini.
