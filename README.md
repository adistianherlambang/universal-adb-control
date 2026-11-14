<div align="center">
  <img src="assets/adbLogo.jpg" alt="Universal ADB Control Logo" width="121" height="121" />
  <h1>Universal ADB Control</h1>
  <p><strong>Aplikasi kontrol nirkabel & kabel untuk mengendalikan HP Android dari Mac secara universal</strong></p>
  <p><em>Seamless Mouse, Keyboard, Layar Terintegrasi Liquid Glass & Sinkronisasi Clipboard Real-Time</em></p>
  <p>
    <img src="https://img.shields.io/badge/Platform-macOS-black?logo=apple" alt="macOS" />
    <img src="https://img.shields.io/badge/Android-11%2B-3DDC84?logo=android&logoColor=white" alt="Android" />
    <img src="https://img.shields.io/badge/Language-Swift%206%20%7C%20ObjC-F05138?logo=swift&logoColor=white" alt="Swift" />
    <img src="https://img.shields.io/badge/UI-Liquid%20Glass%20%28SwiftUI%29-007AFF" alt="Liquid Glass" />
    <img src="https://img.shields.io/badge/License-MIT-blue" alt="License" />
  </p>
</div>

---

## Daftar Isi
- [Fitur Utama](#fitur-utama)
- [Persyaratan Sistem](#persyaratan-sistem)
- [Instalasi & Build](#instalasi--build)
- [Cara Menghubungkan Perangkat](#cara-menghubungkan-perangkat)
- [Pintasan Keyboard](#pintasan-keyboard)
- [Manajemen Layanan CLI](#manajemen-layanan-cli)
- [Konfigurasi Kinerja](#konfigurasi-kinerja)
- [Arsitektur Proyek](#arsitektur-proyek)
- [Lisensi](#lisensi)

---

## Fitur Utama

- **Layar Ponsel Terintegrasi (Unified Studio Window)**:
  Layar HP tersemat langsung di dalam mockup smartphone berdesain *Liquid Glass* native macOS dengan tombol fisik samping interaktif (Volume & Power) dan dock navigasi melayang (Kembali, Beranda, Recents).
- **Kendali Mouse & Keyboard Tanpa Jeda**:
  Alihkan kendali kursor dan pengetikan dari Mac ke Android secara instan dengan pintasan global `⌘ + ⌥ + T` tanpa perlu memegang ponsel.
- **Universal Clipboard Sync 2-Arah**:
  Sinkronisasi teks, rich text, dan berkas secara otomatis antara clipboard macOS (`NSPasteboard`) dan Android melalui koneksi soket TCP berkecepatan tinggi.
- **Pairing QR Code Otomatis (Android 11+)**:
  Cukup scan QR Code langsung dari menu *Opsi Pengembang > Proses debug nirkabel* di ponsel untuk otentikasi TLS dan koneksi otomatis tanpa mengetik alamat IP atau port manual.
- **Streaming 60 FPS Ultra-Rendah Latensi**:
  Didukung hardware encoding H.264/H.265 dengan jitter buffer dinamis untuk menjaga kestabilan transmisi Wi-Fi tanpa *lag* atau patah-patah.
- **HUD Metrik Real-Time (FPS & ms)**:
  Indikator kaca di bilah atas yang menampilkan framerate aktual (FPS) serta latensi transmisi jaringan (ms) secara langsung saat streaming aktif.
- **Rotasi Otomatis & Sinkronisasi Posisi**:
  Rasio layar dan geometri jendela beradaptasi otomatis mengikuti orientasi ponsel (Portret & Lanskap), dengan penguncian posisi presisi tinggi saat jendela Mac digeser.

---

## Persyaratan Sistem

- **Mac**: macOS 14.0 (Sonoma) atau lebih baru (Apple Silicon `arm64`).
- **Android**: Android 11 (API 30) atau lebih baru untuk Wireless Debugging, atau Android 7+ via kabel USB.
- **Dependensi Sistem**:
  ```bash
  brew install --cask android-platform-tools
  brew install scrcpy
  ```

---

## Instalasi & Build

### 1. Kompilasi & Buat macOS App Bundle
Jalankan skrip bundling otomatis untuk mengompilasi biner native dan menghasilkan `Universal ADB Control.app`:
```bash
git clone https://github.com/adistianherlambang/universal-adb-control.git
cd universal-adb-control
chmod +x build.sh bundle_app.sh
./bundle_app.sh
```

### 2. Membuka Aplikasi
Aplikasi yang sudah selesai dikompilasi siap dibuka langsung dari:
```bash
open "bin/Universal ADB Control.app"
```
*(Salinan juga otomatis terpasang di folder `/Applications/Universal ADB Control.app`).*

---

## Cara Menghubungkan Perangkat

Aplikasi mendukung 3 mode koneksi fleksibel melalui popover **Tambah Perangkat**:

1. **Kode QR (Rekomendasi - Android 11+)**:
   - Buka **Pengaturan > Opsi Pengembang > Proses debug nirkabel (*Wireless debugging*)**.
   - Pilih **Pasangkan dengan kode QR (*Pair device with QR code*)**.
   - Arahkan kamera ponsel ke QR code di aplikasi Mac. Perangkat akan terpasang dan tersambung otomatis.

2. **Koneksi IP Langsung / Pairing Kode**:
   - Masukkan alamat `IP:Port` dan 6-digit kode pairing yang tertera pada ponsel Android.

3. **Mode USB ke Wi-Fi Instan**:
   - Sambungkan HP via kabel USB sekali, lalu aktifkan mode Wi-Fi melalui aplikasi (`adb tcpip 5555`). Setelah aktif, kabel USB dapat dicabut dan HP tetap terkoneksi nirkabel.

---

## Pintasan Keyboard

| Pintasan | Tindakan |
| :--- | :--- |
| **`⌘ + ⌥ + T`** | Mulai / Berhenti streaming layar & alihkan fokus kontrol |
| **`⌘ + Q`** | Tutup aplikasi Universal ADB Control |
| **`⌘ + W`** | Sembunyikan jendela ke background (tetap aktif di Menu Bar) |
| **`Escape`** | Tombol Kembali (*Android Back*) |
| **Tombol Volume / Power** | Dapat ditekan langsung pada tombol fisik di sisi kanan bodi mockup |

---

## Manajemen Layanan CLI

Selain antarmuka grafis, Universal ADB Control menyediakan utilitas CLI untuk mengelola background daemon (`universal-adb-control-daemon`):

```bash
# Memeriksa status layanan background & daftar perangkat
universal-adb-control status

# Mengelola daemon sinkronisasi clipboard
universal-adb-control start
universal-adb-control stop
universal-adb-control restart

# Memantau log aktivitas secara real-time
universal-adb-control logs

# Membuka aplikasi GUI utama
universal-adb-control gui
```

---

## Konfigurasi Kinerja

Konfigurasi preferensi streaming tersimpan di `~/.universal-adb-control/config.conf` dan dapat diubah secara visual melalui GUI:

```conf
# Lokasi biner ADB
ADB=/opt/homebrew/bin/adb

# Interval sinkronisasi clipboard (ms)
SYNC_INTERVAL_MS=300

# Pengaturan streaming video
VIDEO_BITRATE=3M
MAX_SIZE=1280
MAX_FPS=60
VIDEO_BUFFER_MS=15
VIDEO_CODEC=h265
```

---

## Arsitektur Proyek

```text
universal-adb-control/
├── assets/                             # Identitas branding resmi & iconset macOS (.icns)
│   ├── adbLogo.jpg                     # Logo resmi asli ADB Android
│   ├── adbLogo.png                     # Logo format PNG resolusi tinggi
│   └── AppIcon.icns                    # macOS Application Iconset (16px - 1024px retina)
├── bin/                                # Biner hasil build & macOS Application Bundle (.app)
├── src/
│   ├── cli/                            # Skrip CLI manajer instalasi & LaunchAgent
│   ├── daemon/                         # Background daemon & sinkronisasi clipboard 2-arah
│   ├── frame/                          # Dylib injeksi Cocoa/AppKit untuk display scrcpy
│   ├── gui/                            # Antarmuka Liquid Glass SwiftUI & manajer state
│   └── helper/                         # Helper launcher biner scrcpy terisolasi
├── build.sh                            # Skrip kompilasi universal clang & swiftc
├── bundle_app.sh                       # Skrip perakit struktur macOS App Bundle (.app)
└── README.md                           # Dokumentasi teknis proyek
```

---

## Lisensi

Proyek ini dirilis di bawah lisensi [MIT](LICENSE).
