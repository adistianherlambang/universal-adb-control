# Universal ADB Control

Aplikasi kontrol nirkabel & kabel untuk mengendalikan HP Android dari Mac secara universal (Mouse, Keyboard, dan Sinkronisasi Clipboard dua arah secara instan).

---

## Fitur Utama

- **GUI & Menu Bar macOS**: Antarmuka native SwiftUI/AppKit modern dengan kontrol status bar di Menu Bar macOS.
- **Universal Clipboard Sync**: Sinkronisasi clipboard real-time 2 arah (Teks, Gambar, Berkas) antara macOS dan Android via socket TCP berkecepatan tinggi.
- **Seamless Mouse & Keyboard Control**: Alihkan kendali mouse dan keyboard ke HP Android secara instan dengan pintasan global `⌘ + ⌥ + T` (Command + Option + T).
- **Tampilan Emulator Android (Bezel & Kamera)**:
  - Jendela smartphone proporsional (380 × 820 pt), bukan fullscreen.
  - Bezel melengkung halus (*Corner Radius 36 pt*) dengan punch-hole camera realistis dan speaker ear-piece.
  - Dapat di-drag / dipindahkan bebas di atas layar Mac dengan menarik header bezel atas.
- **Optimasi Streaming Wi-Fi Ultra-Rendah Latensi**:
  - Hardware encoding H.265 (HEVC) hemat bandwidth hingga 50%.
  - Pembatasan resolusi adaptif (`max-size=1280`) untuk latensi encoding < 4 ms.
  - Penguncian 60 FPS stabil.
  - Jitter buffer 15 ms untuk menyerap fluktuasi sinyal nirkabel tanpa lag/patah-patah.
- **Device Management**: Deteksi otomatis perangkat ADB USB & Wi-Fi dengan fitur *one-click connect/disconnect*.
- **Background Daemon & CLI**: Berjalan stabil di latar belakang via macOS LaunchAgent (`com.universal.adb.control.daemon`).

---

## Struktur Proyek

```text
universal-adb-control/
├── bin/                       # Biner hasil build & App Bundle (gitignored)
├── src/
│   ├── cli/                   # Skrip CLI manager (universal-adb-control)
│   ├── daemon/                # Background sync & control daemon (Swift)
│   └── gui/                   # GUI SwiftUI & Menu Bar macOS
├── build.sh                   # Skrip kompilasi biner daemon & GUI
├── bundle_app.sh              # Skrip pembuatan macOS App Bundle (.app)
└── README.md
```

---

## Cara Kompilasi & Menjalankan

### 1. Build Biner & macOS App Bundle
```bash
chmod +x build.sh bundle_app.sh
./bundle_app.sh
```

Aplikasi macOS siap dibuka melalui:
```bash
open "bin/Universal ADB Control.app"
```

### 2. Menggunakan CLI
```bash
# Cek status layanan daemon & koneksi perangkat
universal-adb-control status

# Kontrol daemon
universal-adb-control start
universal-adb-control stop
universal-adb-control restart

# Memantau log aktivitas
universal-adb-control logs
```

### 3. Pintasan Global Kontrol Layar Penuh
- Tekan **`⌘ + Option + T`** di mana saja untuk mengalihkan mouse dan keyboard ke HP Android.
- Tekan **`⌘ + Option + T`** kembali untuk menyembunyikan kontrol dan mengembalikan kursor ke layar Mac.

---

## Konfigurasi Kinerja (`config.conf`)

Konfigurasi disimpan di `~/.universal-adb-control/config.conf` atau dapat diatur via tab **Pengaturan** di GUI:

```conf
# Universal ADB Control Configuration
ADB=/opt/homebrew/bin/adb
DEVICE=
SYNC_INTERVAL_MS=300
VIDEO_BITRATE=3M
MAX_SIZE=1280
MAX_FPS=60
VIDEO_BUFFER_MS=15
VIDEO_CODEC=h265
```

---

## Lisensi
MIT License
