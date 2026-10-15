# Katarina AI — Current Project Handoff

Updated: **2026-10-15 (Asia/Jakarta)**.

Mulai dari [status proyek terkini](PROJECT_STATUS.md),
[changelog](../CHANGELOG.md), dan
[aturan GitHub-first](operations/GITHUB_FIRST_DEVELOPMENT.md).

Arsitektur canonical terbaru: `UnifiedKatarinaBrain`, satu instance observer,
14 modul dalam registry dan satu memori bersama untuk Fast/Deep. Management,
11 spesialis, workplan, script dan workflow pemanggil sudah dihapus berdasarkan
instruksi Owner 15 Oktober 2026. Risk Governor tetap independen.

Pengujian perubahan: 1.270 unit, 109 static (4 skipped), 49 integration.
Tidak ada order atau live execution. GitHub dan checkout kerja disamakan pada
commit hasil merge; checkout, memori dan proses VPS belum diverifikasi.

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
