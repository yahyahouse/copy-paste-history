# ClipHistory

Aplikasi menu bar macOS yang ringan untuk riwayat copy. Native Swift + AppKit, tanpa dependency.

## Build

```bash
xcode-select --install   # kalau belum ada
./build.sh
mv ClipHistory.app /Applications/
open /Applications/ClipHistory.app
```

Butuh macOS 13+.

## Fitur

• Riwayat 50 teks terakhir, tanpa duplikat
• Cmd+Shift+V membuka menu di posisi kursor, item yang dipilih langsung di-paste
• Tombol 1–9 untuk pilih cepat
• Tahan Option untuk hapus satu item
• Teks dari password manager otomatis diabaikan
• Riwayat tersimpan di `~/Library/Application Support/ClipHistory/history.json`
• Opsi "Buka saat Login"

## Auto-paste

Klik "Aktifkan Auto-Paste…" di menu, lalu izinkan ClipHistory di System Settings → Privacy & Security → Accessibility. Setelah build ulang, izin perlu dicentang ulang.

## Konfigurasi

Ubah konstanta di bagian atas `main.swift` (jumlah item, hotkey).
