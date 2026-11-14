<div align="center">
  <img src="adbLogo.jpg" alt="Universal ADB Control Logo" width="121" height="121" />
  <h1>Universal ADB Control</h1>
  <p><strong>Aplikasi kontrol nirkabel & kabel untuk mengendalikan HP Android dari Mac secara universal</strong></p>
  <p>
    <img src="https://img.shields.io/badge/Platform-macOS-black?logo=apple" alt="macOS" />
    <img src="https://img.shields.io/badge/Android-11%2B-3DDC84?logo=android&logoColor=white" alt="Android" />
    <img src="https://img.shields.io/badge/Language-Swift%206%20%7C%20ObjC-F05138?logo=swift&logoColor=white" alt="Swift" />
    <img src="https://img.shields.io/badge/UI-Liquid%20Glass-007AFF" alt="Liquid Glass" />
    <img src="https://img.shields.io/badge/License-MIT-blue" alt="License" />
  </p>
</div>

---

## Fitur Utama

- **Layar HP Menyatu (Unified Window)**: Tampilan layar Android terintegrasi langsung di dalam mockup ponsel berdesain Liquid Glass native macOS.
- **Mouse & Keyboard Universal**: Kendalikan Android menggunakan keyboard dan trackpad Mac via pintasan global `⌘ + ⌥ + T`.
- **Sinkronisasi Clipboard 2-Arah**: Teks dan file tersinkronisasi otomatis secara instan antara Mac dan Android.
- **Pairing QR Code & Nirkabel**: Pasangkan perangkat Android 11+ via kode QR atau koneksi Wi-Fi langsung tanpa kabel.
- **Streaming 60 FPS Rendah Latensi**: Hardware encoding H.264/H.265 dengan HUD metrik FPS dan latensi (ms) real-time.
- **Rotasi Otomatis**: Orientasi layar dan ukuran jendela beradaptasi otomatis mengikuti orientasi ponsel (Portret & Lanskap).

---

## Cara Kompilasi & Menjalankan

### Build & Buka Aplikasi
```bash
./bundle_app.sh
open "bin/Universal ADB Control.app"
```

### Menggunakan CLI
```bash
universal-adb-control status    # Cek status koneksi perangkat
universal-adb-control start     # Jalankan background daemon
universal-adb-control stop      # Hentikan background daemon
universal-adb-control logs      # Pantau log aktivitas
```

---

## Pintasan Keyboard

| Pintasan | Fungsi |
| :--- | :--- |
| `⌘ + ⌥ + T` | Mulai / Berhenti streaming & alihkan kontrol |
| `⌘ + Q` / `⌘ + W` | Keluar dari aplikasi / sembunyikan jendela |

---

## Struktur Berkas

```text
universal-adb-control/
├── assets/                             # Aset logo resmi & icon macOS (.icns)
│   ├── adbLogo.jpg                     # Logo asli ADB Android
│   ├── adbLogo.png                     # Logo format PNG
│   └── AppIcon.icns                    # Iconset aplikasi (.app)
├── src/
│   ├── cli/                            # Skrip command-line universal-adb-control
│   ├── daemon/                         # Background daemon & sinkronisasi clipboard
│   ├── frame/                          # Dylib penempel layar scrcpy (DeviceFrameOverlay)
│   ├── gui/                            # Antarmuka Liquid Glass SwiftUI & manajemen state
│   └── helper/                         # Helper launcher aplikasi display
├── build.sh                            # Skrip kompilasi biner (swiftc & clang)
├── bundle_app.sh                       # Skrip pembuatan macOS App Bundle (.app)
└── README.md                           # Dokumentasi proyek
```

---

## Lisensi

Didistribusikan di bawah lisensi MIT.
