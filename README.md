# ClipHistory

Aplikasi menu bar macOS yang ringan untuk riwayat copy. Native Swift + AppKit, tanpa dependency.

## Download

Ambil file `.dmg` terbaru di halaman [Releases](https://github.com/yahyahouse/copy-paste-history/releases/latest), buka, lalu seret ClipHistory ke folder Applications.

Karena app belum di-notarize Apple, saat pertama dibuka akan muncul peringatan. Jalankan sekali:

```bash
xattr -dr com.apple.quarantine /Applications/ClipHistory.app
```

Atau klik kanan app → Open → Open.

Butuh macOS 13+, jalan di Apple Silicon dan Intel.

## Build sendiri

```bash
xcode-select --install   # kalau belum ada
./build.sh               # hasil: ClipHistory.app
./make-dmg.sh 1.0.0      # hasil: ClipHistory-1.0.0.dmg
```

## Rilis versi baru

```bash
git tag v1.0.1
git push origin v1.0.1
```

GitHub Actions akan build DMG dan menaruhnya di Releases otomatis.

## Fitur

• Riwayat 50 teks terakhir, tanpa duplikat
• Cmd+Shift+V membuka menu di posisi kursor, item yang dipilih langsung di-paste
• Tombol 1–9 untuk pilih cepat
• Option+klik item untuk menghapusnya
• Teks dari password manager otomatis diabaikan
• Riwayat tersimpan di `~/Library/Application Support/ClipHistory/history.json`
• Opsi "Buka saat Login"

## Auto-paste

Klik "Aktifkan Auto-Paste…" di menu, lalu izinkan ClipHistory di System Settings → Privacy & Security → Accessibility. Setelah build ulang, izin perlu dicentang ulang.

## Konfigurasi

Ubah konstanta di bagian atas `main.swift` (jumlah item, hotkey).
