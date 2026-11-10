import SwiftUI
import AppKit

@available(macOS 11.0, *)
struct MainView: View {
    @ObservedObject var state: AppState
    @State private var selectedTab: Int = 0
    @State private var wifiIp: String = ""
    @State private var wifiPort: String = "5555"

    var body: some View {
        HStack(spacing: 0) {
            // Sisi Kiri: Panel Pengaturan, Status & Layanan
            VStack(spacing: 0) {
                // Header Bar
                headerBar
                
                Divider()
                
                // Tab Selection
                tabSelector
                
                Divider()
                
                // Tab Content
                Group {
                    if selectedTab == 0 {
                        DashboardView(state: state)
                    } else if selectedTab == 1 {
                        DevicesView(state: state, wifiIp: $wifiIp, wifiPort: $wifiPort)
                    } else if selectedTab == 2 {
                        SettingsView(state: state)
                    } else {
                        LogsView(state: state)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                Divider()
                
                // Bottom Status Bar
                statusBar
            }
            .frame(minWidth: 580, maxWidth: .infinity)
            
            Divider()
            
            // Sisi Kanan: Layar Android Terintegrasi (Mode Emulator)
            EmulatorPaneView(state: state)
                .frame(width: 400)
        }
        .frame(minWidth: 1020, minHeight: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .alert(isPresented: $state.showAlert) {
            Alert(
                title: Text("Universal ADB Control"),
                message: Text(state.alertMessage ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    // MARK: - Subviews
    
    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "ipad.and.iphone")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Universal ADB Control")
                    .font(.headline)
                    .fontWeight(.bold)
                Text("Seamless Mouse, Keyboard & Unified Display")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Tombol Kontrol Layar Terintegrasi
            Button(action: {
                state.toggleDisplay()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: state.isScrcpyActive ? "stop.circle.fill" : "play.circle.fill")
                        .foregroundColor(state.isScrcpyActive ? .red : .green)
                    Text(state.isScrcpyActive ? "Hentikan Layar" : "Mulai Kontrol (⌘⌥T)")
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .buttonStyle(PlainButtonStyle())
            .background(state.isScrcpyActive ? Color.red.opacity(0.12) : Color.accentColor.opacity(0.12))
            .cornerRadius(6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private var tabSelector: some View {
        HStack(spacing: 8) {
            tabButton(title: "Status & Kontrol", icon: "gauge", index: 0)
            tabButton(title: "Perangkat", icon: "laptopcomputer.and.iphone", index: 1)
            tabButton(title: "Pengaturan", icon: "gearshape", index: 2)
            tabButton(title: "Log Aktivitas", icon: "list.bullet.rectangle", index: 3)
            Spacer()
            
            Button(action: { state.refreshAll() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.trailing, 14)
            .help("Muat ulang data")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    private func tabButton(title: String, icon: String, index: Int) -> some View {
        Button(action: { selectedTab = index }) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(selectedTab == index ? .semibold : .regular)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(selectedTab == index ? Color.accentColor.opacity(0.18) : Color.clear)
            .cornerRadius(6)
            .foregroundColor(selectedTab == index ? .accentColor : .primary)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var statusBar: some View {
        HStack {
            Circle()
                .fill(state.isDaemonRunning ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            Text(state.isDaemonRunning ? "Daemon Aktif (PID: \(state.daemonPid.map { String($0) } ?? "-"))" : "Daemon Tidak Aktif")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text("Pintasan Keyboard: ⌘ + ⌥ + T")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
    }
}

// MARK: - Emulator Android Pane (Sisi Kanan)
@available(macOS 11.0, *)
struct EmulatorPaneView: View {
    @ObservedObject var state: AppState
    
    var body: some View {
        VStack(spacing: 12) {
            // Header Panel Emulator
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "iphone")
                        .foregroundColor(.accentColor)
                    Text("Emulator Android")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                // Status Badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(state.isScrcpyActive ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(state.isScrcpyActive ? "Aktif" : "Siaga")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            
            // Bodi Ponsel Smartphone (Emulator Frame)
            ZStack {
                // Sasis Luar Bodi Ponsel
                RoundedRectangle(cornerRadius: 36)
                    .fill(Color(white: 0.10))
                    .frame(width: 350, height: 576)
                    .overlay(
                        RoundedRectangle(cornerRadius: 36)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color(white: 0.32), Color(white: 0.18), Color(white: 0.28)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3.5
                            )
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
                
                VStack(spacing: 0) {
                    // Bezel Atas: Speaker Grill & Punch-Hole Camera
                    ZStack {
                        // Speaker Ear-Piece
                        RoundedRectangle(cornerRadius: 1.75)
                            .fill(Color(white: 0.26))
                            .frame(width: 44, height: 3.5)
                            .offset(y: -8)
                        
                        // Punch-Hole Camera Tengah
                        ZStack {
                            Circle()
                                .fill(Color(white: 0.22))
                                .frame(width: 15, height: 15)
                            Circle()
                                .fill(Color.black)
                                .frame(width: 12, height: 12)
                            Circle()
                                .fill(Color(white: 0.6).opacity(0.8))
                                .frame(width: 3, height: 3)
                                .offset(x: 2, y: -2)
                        }
                        .offset(y: 4)
                    }
                    .frame(width: 334, height: 28)
                    
                    // Area Layar HP
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black)
                            .frame(width: 334, height: 494)
                        
                        if state.isScrcpyActive {
                            // Kontainer Host Tampilan Layar yang Dihubungkan Langsung
                            PhoneScreenHostView(state: state)
                                .frame(width: 334, height: 494)
                                .cornerRadius(20)
                        } else {
                            // Layar Standby Saat Belum Dihubungkan
                            VStack(spacing: 12) {
                                Spacer()
                                
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 36))
                                    .foregroundColor(.accentColor)
                                
                                Text("Universal Control Siaga")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                
                                Text(state.connectedDevice == "-" ? "Hubungkan perangkat ADB" : state.connectedDevice)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                                
                                Button(action: {
                                    state.startDisplay()
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "play.fill")
                                        Text("Hubungkan Layar")
                                    }
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color.accentColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding(.top, 4)
                                
                                Spacer()
                            }
                            .frame(width: 334, height: 494)
                        }
                    }
                    .frame(width: 334, height: 494)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    
                    // Chin Bawah: Tombol Navigasi Fisik Android
                    HStack(spacing: 20) {
                        Button(action: { state.sendBack() }) {
                            Image(systemName: "arrow.backward")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(white: 0.65))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Kembali (Back)")
                        
                        Button(action: { state.sendHome() }) {
                            Image(systemName: "circle")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color(white: 0.65))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Beranda (Home)")
                        
                        Button(action: { state.sendRecents() }) {
                            Image(systemName: "square")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(white: 0.65))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Aplikasi Terkini (Recents)")
                        
                        Button(action: { state.sendPower() }) {
                            Image(systemName: "power")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(white: 0.65))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Kunci Layar (Power)")
                        
                        Button(action: { state.sendVolumeDown() }) {
                            Image(systemName: "speaker.minus.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(white: 0.65))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Volume Turun")
                        
                        Button(action: { state.sendVolumeUp() }) {
                            Image(systemName: "speaker.plus.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(white: 0.65))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Volume Naik")
                    }
                    .frame(width: 334, height: 38)
                }
            }
            .frame(width: 350, height: 576)
            
            // Catatan Pintasan Bawah
            Text("Tekan ⌘⌥T untuk mengontrol langsung dengan mouse & keyboard")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
}

// MARK: - Host Container NSView untuk Mengukur Koordinat Layar Piksel Tepat
@available(macOS 11.0, *)
struct PhoneScreenHostView: NSViewRepresentable {
    @ObservedObject var state: AppState
    
    func makeNSView(context: Context) -> HostContainerNSView {
        let view = HostContainerNSView()
        view.onFrameChanged = { [weak state] rect in
            state?.updateHostGeometry(rect: rect)
        }
        return view
    }
    
    func updateNSView(_ nsView: HostContainerNSView, context: Context) {}
}

class HostContainerNSView: NSView {
    var onFrameChanged: ((NSRect) -> Void)?
    
    override func layout() {
        super.layout()
        reportGeometry()
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportGeometry()
    }
    
    private func reportGeometry() {
        if self.window != nil {
            let rectInWindow = self.convert(self.bounds, to: nil)
            onFrameChanged?(rectInWindow)
        }
    }
}

// MARK: - Dashboard View
@available(macOS 11.0, *)
struct DashboardView: View {
    @ObservedObject var state: AppState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Service Control Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Layanan Daemon")
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        Button(action: { state.startService() }) {
                            Label("Start", systemImage: "play.fill")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                        .disabled(state.isDaemonRunning)
                        
                        Button(action: { state.stopService() }) {
                            Label("Stop", systemImage: "stop.fill")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                        .disabled(!state.isDaemonRunning)
                        
                        Button(action: { state.restartService() }) {
                            Label("Restart", systemImage: "arrow.clockwise")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                        
                        Spacer()
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                // Realtime Sync Status Grid
                VStack(alignment: .leading, spacing: 12) {
                    Text("Status Sinkronisasi Real-Time")
                        .font(.headline)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        statusItem(label: "Perangkat Terhubung", value: state.connectedDevice, icon: "antenna.radiowaves.left.and.right")
                        statusItem(label: "Android Agent DEX", value: state.isAgentRunningOnDevice ? "Aktif" : "Tidak Aktif", icon: "cpu")
                        statusItem(label: "Arah Sync Terakhir", value: state.lastDirection, icon: "arrow.left.arrow.right")
                        statusItem(label: "Tipe Data Terakhir", value: state.lastContentType, icon: "doc.on.clipboard")
                        statusItem(label: "Waktu Sync Terakhir", value: state.lastSyncTime, icon: "clock")
                        statusItem(label: "Kontrol Mouse/Keyboard", value: state.isScrcpyActive ? "Sedang Mengontrol" : "Siap (⌘⌥T)", icon: "magicmouse")
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            .padding(16)
        }
    }
    
    private func statusItem(label: String, value: String, icon: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
    }
}

// MARK: - Devices View
@available(macOS 11.0, *)
struct DevicesView: View {
    @ObservedObject var state: AppState
    @Binding var wifiIp: String
    @Binding var wifiPort: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Wi-Fi Connect Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Hubungkan ADB via Wi-Fi")
                    .font(.headline)
                
                HStack(spacing: 10) {
                    TextField("IP Address (contoh: 192.168.1.146)", text: $wifiIp)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    TextField("Port", text: $wifiPort)
                        .frame(width: 80)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button("Hubungkan") {
                        state.connectWifi(ip: wifiIp, port: wifiPort)
                    }
                    .buttonStyle(DefaultButtonStyle())
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // Device List
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Daftar Perangkat Terdeteksi (\(state.adbDevices.count))")
                        .font(.headline)
                    Spacer()
                    Button(action: { state.refreshDevices() }) {
                        Label("Segarkan", systemImage: "arrow.clockwise")
                    }
                }
                
                if state.adbDevices.isEmpty {
                    Text("Tidak ada perangkat yang terdeteksi via ADB.")
                        .foregroundColor(.secondary)
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    List {
                        ForEach(state.adbDevices) { dev in
                            HStack {
                                Image(systemName: dev.isWifi ? "wifi" : "cable.connector")
                                    .foregroundColor(.accentColor)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dev.serial)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text("\(dev.model) • Status: \(dev.state)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if dev.isWifi {
                                    Button("Putuskan") {
                                        state.disconnectWifi(serial: dev.serial)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(4)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            Spacer()
        }
        .padding(16)
    }
}

// MARK: - Settings View
@available(macOS 11.0, *)
struct SettingsView: View {
    @ObservedObject var state: AppState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Pengaturan Sistem")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Path Eksekusi ADB")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        TextField("Path adb binary", text: $state.adbPath)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Target Device Serial (Opsional)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        TextField("Kosongkan untuk otomatis mendeteksi perangkat pertama", text: $state.preferredDevice)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Interval Polling Sinkronisasi (ms)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        TextField("300", text: $state.syncIntervalMs)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    Text("Optimasi Kinerja Streaming Wi-Fi")
                        .font(.subheadline)
                        .fontWeight(.bold)
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Video Bitrate (Rekomendasi 2M-4M)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("3M", text: $state.videoBitrate)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Resolusi Maksimal")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("1280", text: $state.maxSize)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Maksimal FPS")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("60", text: $state.maxFps)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Video Buffer Jitter (ms)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("15", text: $state.videoBufferMs)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Video Codec (h265 / h264)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("h265", text: $state.videoCodec)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                    
                    HStack {
                        Button("Simpan Pengaturan") {
                            state.saveConfig()
                        }
                        .buttonStyle(DefaultButtonStyle())
                        
                        Button("Muat Ulang dari Berkas") {
                            state.loadConfig()
                        }
                    }
                    .padding(.top, 8)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                // Shortcut info card
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pintasan Keyboard Global")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("• Tekan ⌘ + ⌥ + T (Command + Option + T) di mana saja untuk mengalihkan mouse dan keyboard langsung ke HP Android Anda.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("• Tekan ⌘ + ⌥ + T kembali untuk membebaskan kursor mouse dan kembali ke macOS.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("• Sinkronisasi teks, gambar, dan berkas di clipboard berjalan otomatis dua arah secara real-time.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            .padding(16)
        }
    }
}

// MARK: - Logs View
@available(macOS 11.0, *)
struct LogsView: View {
    @ObservedObject var state: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Log Daemon Terbaru")
                    .font(.headline)
                Spacer()
                Button(action: { state.refreshLogs() }) {
                    Label("Segarkan", systemImage: "arrow.clockwise")
                }
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(state.logs.indices, id: \.self) { idx in
                        Text(state.logs[idx])
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(16)
    }
}
