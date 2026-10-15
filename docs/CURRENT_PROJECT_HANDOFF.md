# Katarina AI — Current Project Handoff

Updated: **2026-10-15 (Asia/Jakarta)**.

Mulai dari [status proyek terkini](PROJECT_STATUS.md),
[changelog](../CHANGELOG.md), dan
[aturan GitHub-first](operations/GITHUB_FIRST_DEVELOPMENT.md).

Baseline tervalidasi terakhir: `958ae7d692330f4137144222331f8b6081b3464b`.
Body CI dan Stage 35 lulus. Sepuluh komponen unified terintegrasi dalam verifikasi
offline, tanpa order dan tanpa live execution. GitHub dan checkout kerja cocok;
kesamaan dengan checkout/proses VPS belum diverifikasi.

Repository publik tetap dimiliki akun `alfaauliau-katarinaAI`; main wajib PR dan
CI, dengan larangan force-push/penghapusan. Ada 42 branch dengan commit unik yang
dipertahankan. Jangan reset atau hapus sejarah unik untuk sekadar menyamakan SHA.

Akses CLI lintas perangkat: [panduan dan batas autentikasi](operations/GITHUB_ACCESS.md).
Jangan menyalin token aplikasi ChatGPT, cookie browser, atau kredensial ke source,
Actions artifact, issue maupun chat. Jangan menonaktifkan proteksi untuk mengatasi
hambatan akses.

Dokumen terdahulu disimpan sebagai [arsip 10 Oktober](handoff/PROJECT_HANDOFF_20261010.md)
dan [checkpoint sampai 13 Oktober](handoff/KATARINA_START_NEXT_CHAT_20261013.md).
Catatan host lama di dalamnya bukan keadaan VPS saat ini.
