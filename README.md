# Universal ADB Control

Aplikasi kontrol nirkabel & kabel untuk mengendalikan HP Android dari Mac secara universal (Mouse, Keyboard, dan Sinkronisasi Clipboard dua arah secara instan).

---

## Fitur Utama

- **Desain Liquid Glass Minimalis**: Antarmuka transparan modern menggunakan material *Liquid Glass* native macOS, tanpa badge warna-warni, tanpa dinding teks yang membingungkan, fokus murni pada pengalaman interaksi perangkat.
- **Layar Android Menyatu Langsung (Unified Studio Window)**:
  - Layar HP dengan bezel bodi smartphone melengkung, punch-hole camera, dan tombol samping fisik (Volume & Power) terintegrasi langsung di dalam jendela Universal ADB Control (tidak ada jendela terpisah).
  - Dock kontrol kaca melayang interaktif: Kembali (◀), Beranda (●), Aplikasi Terkini (■), dan tombol putar/henti instan.
  - Zero Presence: scrcpy terbungkus 100% dan tidak pernah muncul di macOS Dock, App Switcher (`⌘+Tab`), maupun Menu Bar.
- **Universal Clipboard Sync**: Sinkronisasi clipboard real-time 2 arah (Teks, Gambar, Berkas) antara macOS dan Android via socket TCP berkecepatan tinggi.
- **Seamless Mouse & Keyboard Control**: Alihkan kendali mouse dan keyboard ke HP Android secara instan dengan pintasan global `⌘ + ⌥ + T` (Command + Option + T).
- **Optimasi Streaming Wi-Fi Ultra-Rendah Latensi**:
  - Hardware encoding H.265 (HEVC) hemat bandwidth hingga 50%.
  - Pembatasan resolusi adaptif (`max-size=1280`) untuk latensi encoding < 4 ms.
  - Penguncian 60 FPS stabil.
  - Jitter buffer 15 ms untuk menyerap fluktuasi sinyal nirkabel tanpa lag/patah-patah.
- **Device Management**: Deteksi otomatis perangkat ADB USB & Wi-Fi dengan fitur *one-click connect/disconnect*.
- **Background Daemon & CLI**: Berjalan stabil di latar belakang via macOS LaunchAgent (`com.universal.adb.control.daemon`).

---

## Struktur Proyek & Blueprint Berkas

Setiap berkas dalam arsitektur Universal ADB Control dirancang dengan tanggung jawab modular dan spesifik:

```text
universal-adb-control/
├── bin/                                # Biner hasil kompilasi & macOS App Bundle (gitignored)
├── src/
│   ├── cli/
│   │   └── universal-adb-control       # Skrip CLI manajer instalasi & layanan LaunchAgent
│   ├── daemon/
│   │   ├── main.swift                  # Titik masuk executable background daemon
│   │   ├── AdbTransport.swift          # Komunikasi ADB socket & port forwarding TCP
│   │   ├── ClipboardDaemon.swift       # Mesin sinkronisasi clipboard 2 arah real-time
│   │   ├── ControlManager.swift        # Pengelola hotkey ⌘⌥T & orkestrator kontrol GUI
│   │   ├── Models.swift                # Definisi model data, konfigurasi, & logger
│   │   └── PasteboardManager.swift     # Abstraksi baca/tulis NSPasteboard macOS
│   ├── frame/
│   │   └── DeviceFrameOverlay.m        # Dylib injeksi macOS (stealth, layout sync, focus lock)
│   ├── gui/
│   │   ├── main.swift                  # Entry point AppKit, Menu Utama sistem, & jendela kaca
│   │   ├── AppState.swift              # ObservableObject state manager & peluncur display SDK
│   │   └── MainView.swift              # Antarmuka Liquid Glass SwiftUI & mockup smartphone
│   └── helper/
│       └── UniversalADBControlDisplay.c# Launcher C mandiri pembungkus scrcpy dengan dylib
├── build.sh                            # Skrip kompilasi biner modular via clang & swiftc
├── bundle_app.sh                       # Skrip generator macOS App Bundle (.app)
└── README.md                           # Dokumentasi & panduan teknis proyek
```

### Penjelasan Detail Berkas Blueprint

#### 1. Skrip Kompilasi & Bundling (Root)
- **`build.sh`**: Mengompilasi seluruh komponen native proyek menggunakan `clang` (arsitektur universal `arm64` & `arm64e`) dan `swiftc` (target macOS 26.0) ke folder `bin/`.
- **`bundle_app.sh`**: Membungkus hasil kompilasi menjadi struktur macOS Application Bundle mandiri (`Universal ADB Control.app`) yang berisi `Info.plist`, executable GUI, `Helpers/UniversalADBControlDisplay.app`, dan framework dylib pendukung.

#### 2. Modul Manajer CLI (`src/cli/`)
- **`src/cli/universal-adb-control`**: Skrip bash CLI untuk menginstal/menghapus LaunchAgent daemon (`com.universal.adb.control.daemon`), memeriksa status koneksi perangkat ADB, memantau log streaming/clipboard, serta membuka GUI via baris perintah.

#### 3. Modul Background Daemon (`src/daemon/`)
- **`src/daemon/main.swift`**: Titik masuk (*entry point*) executable daemon latar belakang; menginisialisasi daemon clipboard, menangani sinyal sistem, dan menjalankan run loop.
- **`src/daemon/AdbTransport.swift`**: Menangani koneksi soket ADB tingkat rendah, port forwarding TCP untuk agen Android, dan pengiriman perintah ADB shell secara andal.
- **`src/daemon/ClipboardDaemon.swift`**: Mesin sinkronisasi clipboard dua arah berkecepatan tinggi antara macOS (`NSPasteboard`) dan Android (teks, rich text HTML, dan file/gambar).
- **`src/daemon/ControlManager.swift`**: Menangani pintasan global `⌘ + Option + T` menggunakan Carbon Event Manager, mengorkestrasikan pembukaan aplikasi GUI jika sedang tertutup, dan mengarahkan fokus ke jendela emulator.
- **`src/daemon/Models.swift`**: Struktur data payload clipboard, parser konfigurasi file `config.conf` (`DaemonConfig`), dan utilitas sistem logging.
- **`src/daemon/PasteboardManager.swift`**: Membaca dan menulis ke clipboard native macOS (`NSPasteboard`) dengan hashing SHA-256 untuk mencegah *sync echo loop*.

#### 4. Modul Injeksi Frame & Window Overlay (`src/frame/`)
- **`src/frame/DeviceFrameOverlay.m`**: Dynamic library Objective-C (`libUniversalControlFrame.dylib`) yang disisipkan ke scrcpy via `DYLD_INSERT_LIBRARIES`:
  - **Stealth Mode**: Men-swizzle `setActivationPolicy:` ke `NSApplicationActivationPolicyAccessory` sehingga scrcpy tidak pernah memunculkan ikon terpisah di Dock atau App Switcher (`⌘+Tab`).
  - **Sinkronisasi Posisi 60 FPS**: Mengunci ukuran dan koordinat jendela scrcpy tepat di atas mockup layar ponsel pada GUI (`syncEmbeddedWindow`).
  - **Punch-Hole Camera**: Menggambar kamera punch-hole dinamis di atas layar (`UACCameraDotView`).
  - **Focus Lock & Anti-Leak**: Men-swizzle `canBecomeKeyWindow` dan `canBecomeMainWindow` pada `NSWindow` serta mengaktifkan proses secara instan saat layar diklik (`uac_sendEvent:`) sehingga 100% input keyboard dan trackpad masuk ke Android tanpa bocor ke Mac.
  - **Pintasan Keluar Instan**: Mengintersepsi `⌘Q` dan `⌘W` di tingkat Cocoa event loop untuk menghentikan display helper dan aplikasi induk secara serempak.
  - **Anti-Standalone Guard**: Menolak peluncuran jendela scrcpy mengambang di luar GUI (memastikan hanya satu layar yang aktif di dalam GUI).

#### 5. Modul Liquid Glass GUI (`src/gui/`)
- **`src/gui/main.swift`**: Titik masuk aplikasi GUI macOS AppKit (`@main UniversalControlApp` & `AppDelegate`):
  - Mengonfigurasi `NSApp.mainMenu` lengkap (App, Edit, Window) agar pintasan keyboard native macOS (`⌘Q`, `⌘W`, `⌘C`, `⌘V`, `⌘Z`) aktif di seluruh komponen.
  - Membangun jendela transparan berlatar material Liquid Glass (`NSVisualEffectView`).
  - Memasang monitor event lokal untuk penutupan aplikasi dan integrasi menu bar status icon.
- **`src/gui/AppState.swift`**: Pusat manajemen state SwiftUI (`ObservableObject`):
  - Mendeteksi perangkat Android USB & Wi-Fi dan memuat preferensi streaming.
  - Menghitung koordinat piksel area layar ponsel dan menyimpannya ke `~/.universal-adb-control/host_rect.json`.
  - Meluncurkan helper display scrcpy dengan parameter koordinat mutlak (`--keyboard=sdk --mouse=sdk`) untuk sinkronisasi kursor 1:1 dan gestur trackpad mulus.
  - Mengirim tombol fisik Android (Volume Up/Down, Power, Back, Home, Recents) via ADB keyevent.
- **`src/gui/MainView.swift`**: Desain antarmuka modern Liquid Glass SwiftUI:
  - Mockup bodi smartphone proporsional dengan sudut melengkung halus dan tombol fisik samping interaktif.
  - Dock navigasi bawah bergaya kapsul kaca melayang (Kembali, Beranda, Recents, Mulai/Berhenti).
  - Komponen penanda geometri (`ScreenAnchor` / `AnchorView`) untuk sinkronisasi posisi layar overlay.
  - Popover pemilihan perangkat dan pengaturan profil streaming tanpa badge atau teks yang membingungkan.

#### 6. Modul Helper Launcher (`src/helper/`)
- **`src/helper/UniversalADBControlDisplay.c`**: Binary launcher C ringkas yang dikemas di dalam `UniversalADBControlDisplay.app` untuk menyuntikkan `libUniversalControlFrame.dylib` ke scrcpy secara terisolasi tanpa membuat entri Dock baru.

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

# Membuka aplikasi GUI
universal-adb-control gui
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
