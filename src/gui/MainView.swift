import SwiftUI

@available(macOS 11.0, *)
struct MainView: View {
    @ObservedObject var state: AppState
    @State private var selectedTab: Int = 0
    @State private var wifiIp: String = ""
    @State private var wifiPort: String = "5555"

    var body: some View {
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
        .frame(width: 680, height: 500)
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
                .frame(width: 26, height: 26)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Universal ADB Control")
                    .font(.headline)
                    .fontWeight(.bold)
                Text("Seamless Mouse, Keyboard & Clipboard Sync")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Quick Action: Scrcpy Control Button
            Button(action: {
                state.toggleScrcpyControl()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: state.isScrcpyActive ? "stop.circle.fill" : "play.circle.fill")
                        .foregroundColor(state.isScrcpyActive ? .red : .green)
                    Text(state.isScrcpyActive ? "Hentikan Kontrol" : "Mulai Kontrol (⌘⌥T)")
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
            
            Text("Shortcut: ⌘ + ⌥ + T")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
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

