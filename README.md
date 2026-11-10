# Universal ADB Control

Aplikasi kontrol nirkabel & kabel untuk mengendalikan Android dari Mac secara universal (Mouse, Keyboard, dan Sinkronisasi Clipboard dua arah secara instan).

---

## Fitur Utama

- **GUI & Menu Bar macOS**: Dilengkapi antarmuka native SwiftUI/AppKit yang modern dengan status bar item di menu bar atas macOS.
- **Universal Clipboard Sync**: Sinkronisasi clipboard real-time 2 arah (Teks, Gambar, Berkas) antara macOS dan Android via socket TCP berkecepatan tinggi.
- **Seamless Mouse & Keyboard Control**: Beralih kendali mouse dan keyboard ke HP Android langsung menggunakan shortcut global `⌘ + ⌥ + T` (Command + Option + T).
- **Device Management**: Deteksi perangkat USB & Wi-Fi ADB secara otomatis, dengan dukungan *one-click connect/disconnect*.
- **CLI & Background Daemon**: Daemon latar belakang otomatis berjalan via macOS LaunchAgent (`com.universal.adb.control.daemon`).

---

## Struktur Proyek

```text
universal-adb-control/
├── bin/                       # Output biner hasil kompilasi (gitignored)
├── src/
│   ├── cli/                   # Skrip bash CLI manager (universal-adb-control)
│   ├── daemon/                # Source code Swift untuk background sync daemon
│   └── gui/                   # Source code SwiftUI untuk aplikasi GUI & Menu Bar
├── build.sh                   # Skrip otomatis untuk build biner daemon dan GUI
└── README.md
```

---

## Cara Kompilasi

Jalankan perintah berikut di terminal:

```bash
chmod +x build.sh
./build.sh
```

Biner akan tersedia di direktori `bin/`:
- `bin/universal-adb-control-daemon`
- `bin/UniversalADBControlGUI`

---

## Penggunaan

### 1. Menjalankan Aplikasi GUI
```bash
./bin/UniversalADBControlGUI
```

### 2. Menggunakan CLI
```bash
# Cek status layanan
universal-adb-control status

# Mulai / hentikan / restart daemon
universal-adb-control start
universal-adb-control stop
universal-adb-control restart

# Melihat log aktivitas
universal-adb-control logs
```

### 3. Shortcut Kontrol Mouse & Keyboard
- Tekan **`⌘ + Option + T`** untuk mengalihkan mouse dan keyboard ke HP.
- Tekan **`⌘ + Option + T`** kembali untuk melepaskan kursor ke layar Mac.

---

## Lisensi
MIT License
