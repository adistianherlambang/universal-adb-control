import Foundation
import Combine
import Cocoa

public struct ServiceStatusData: Codable {
    public var running: Bool?
    public var connectedDevice: String?
    public var lastSyncTime: String?
    public var lastDirection: String?
    public var lastContentType: String?
    public var pid: Int?
}

public struct AdbDeviceItem: Identifiable, Hashable {
    public var id: String { serial }
    public let serial: String
    public let state: String
    public let model: String
    public let isWifi: Bool
}

public class AppState: ObservableObject {
    @Published public var isDaemonRunning: Bool = false
    @Published public var daemonPid: Int? = nil
    @Published public var connectedDevice: String = "-"
    @Published public var lastSyncTime: String = "-"
    @Published public var lastDirection: String = "-"
    @Published public var lastContentType: String = "-"
    
    @Published public var adbDevices: [AdbDeviceItem] = []
    @Published public var isAgentRunningOnDevice: Bool = false
    @Published public var logs: [String] = []
    
    @Published public var adbPath: String = "/opt/homebrew/bin/adb"
    @Published public var preferredDevice: String = ""
    @Published public var syncIntervalMs: String = "300"
    
    // Konfigurasi performa streaming Wi-Fi
    @Published public var videoBitrate: String = "3M"
    @Published public var maxSize: String = "1280"
    @Published public var maxFps: String = "60"
    @Published public var videoBufferMs: String = "15"
    @Published public var videoCodec: String = "h265"
    
    @Published public var isScrcpyActive: Bool = false
    @Published public var alertMessage: String? = nil
    @Published public var showAlert: Bool = false
    
    // Geometri kontainer layar Android terintegrasi (Embedded)
    public var hostOffsetX: CGFloat = 693.0
    public var hostOffsetY: CGFloat = 70.0
    public var hostWidth: CGFloat = 334.0
    public var hostHeight: CGFloat = 494.0
    
    private var timer: Timer?
    
    public init() {
        loadConfig()
        refreshAll()
        
        // Polling status setiap 2 detik
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }
    
    deinit {
        timer?.invalidate()
        stopDisplay()
    }
    
    public func updateHostGeometry(rect: NSRect) {
        if rect.size.width > 50 && rect.size.height > 50 {
            self.hostOffsetX = rect.origin.x
            self.hostOffsetY = rect.origin.y
            self.hostWidth = rect.size.width
            self.hostHeight = rect.size.height
            
            let json = "{\"offsetX\": \(rect.origin.x), \"offsetY\": \(rect.origin.y), \"width\": \(rect.size.width), \"height\": \(rect.size.height)}"
            let path = ("~/.universal-adb-control/host_rect.json" as NSString).expandingTildeInPath
            try? json.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
    
    public func loadConfig() {
        let confPath = ("~/.universal-adb-control/config.conf" as NSString).expandingTildeInPath
        guard let content = try? String(contentsOfFile: confPath, encoding: .utf8) else { return }
        
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                switch parts[0] {
                case "ADB":
                    self.adbPath = parts[1]
                case "DEVICE":
                    self.preferredDevice = parts[1]
                case "SYNC_INTERVAL_MS":
                    self.syncIntervalMs = parts[1]
                case "VIDEO_BITRATE":
                    self.videoBitrate = parts[1]
                case "MAX_SIZE":
                    self.maxSize = parts[1]
                case "MAX_FPS":
                    self.maxFps = parts[1]
                case "VIDEO_BUFFER_MS":
                    self.videoBufferMs = parts[1]
                case "VIDEO_CODEC":
                    self.videoCodec = parts[1]
                default:
                    break
                }
            }
        }
    }
    
    public func saveConfig() {
        let confPath = ("~/.universal-adb-control/config.conf" as NSString).expandingTildeInPath
        let content = """
        # Universal ADB Control Configuration
        ADB=\(adbPath)
        DEVICE=\(preferredDevice)
        SYNC_INTERVAL_MS=\(syncIntervalMs)
        VIDEO_BITRATE=\(videoBitrate)
        MAX_SIZE=\(maxSize)
        MAX_FPS=\(maxFps)
        VIDEO_BUFFER_MS=\(videoBufferMs)
        VIDEO_CODEC=\(videoCodec)
        """
        do {
            try content.write(toFile: confPath, atomically: true, encoding: .utf8)
            notify(message: "Pengaturan berhasil disimpan!")
        } catch {
            notify(message: "Gagal menyimpan konfigurasi: \(error.localizedDescription)")
        }
    }
    
    public func refreshAll() {
        refreshStatus()
        refreshDevices()
        refreshLogs()
    }
    
    public func refreshStatus() {
        // 1. Read status.json
        let statusPath = ("~/.universal-adb-control/status.json" as NSString).expandingTildeInPath
        if let data = try? Data(contentsOf: URL(fileURLWithPath: statusPath)),
           let json = try? JSONDecoder().decode(ServiceStatusData.self, from: data) {
            self.connectedDevice = json.connectedDevice ?? "-"
            self.lastSyncTime = json.lastSyncTime ?? "-"
            self.lastDirection = json.lastDirection ?? "-"
            self.lastContentType = json.lastContentType ?? "-"
            self.daemonPid = json.pid
        }
        
        // 2. Check process daemon
        let pids = runShell("pgrep -f universal-adb-control-daemon").trimmingCharacters(in: .whitespacesAndNewlines)
        if !pids.isEmpty {
            self.isDaemonRunning = true
            if let firstPid = pids.components(separatedBy: .newlines).first, let p = Int(firstPid) {
                self.daemonPid = p
            }
        } else {
            self.isDaemonRunning = false
            self.daemonPid = nil
        }
        
        // 3. Check display helper process
        let displayPids = runShell("pgrep -f 'UniversalADBControlDisplay'").trimmingCharacters(in: .whitespacesAndNewlines)
        self.isScrcpyActive = !displayPids.isEmpty
        
        // 4. Check agent on device
        let agentRunning = runShell("\(adbPath) shell 'pgrep -f clipboard_agent.dex'").trimmingCharacters(in: .whitespacesAndNewlines)
        self.isAgentRunningOnDevice = !agentRunning.isEmpty
    }
    
    public func refreshDevices() {
        let output = runShell("\(adbPath) devices -l")
        var items: [AdbDeviceItem] = []
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("List of devices") { continue }
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2 {
                let serial = String(parts[0])
                let state = String(parts[1])
                var model = ""
                for part in parts {
                    let s = String(part)
                    if s.hasPrefix("model:") {
                        model = s.replacingOccurrences(of: "model:", with: "")
                    }
                }
                let isWifi = serial.contains(":") || serial.contains("._tcp")
                items.append(AdbDeviceItem(serial: serial, state: state, model: model.isEmpty ? "Android Device" : model, isWifi: isWifi))
            }
        }
        self.adbDevices = items
    }
    
    public func refreshLogs() {
        let logPath = ("~/.universal-adb-control/daemon.log" as NSString).expandingTildeInPath
        if let logText = try? String(contentsOfFile: logPath, encoding: .utf8) {
            let lines = logText.components(separatedBy: .newlines).filter { !$0.isEmpty }
            self.logs = Array(lines.suffix(50))
        }
    }
    
    public func startService() {
        _ = runShell("universal-adb-control start")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.refreshAll()
            self.notify(message: "Layanan dimulai.")
        }
    }
    
    public func stopService() {
        _ = runShell("universal-adb-control stop")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.refreshAll()
            self.notify(message: "Layanan dihentikan.")
        }
    }
    
    public func restartService() {
        _ = runShell("universal-adb-control restart")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.refreshAll()
            self.notify(message: "Layanan dimuat ulang.")
        }
    }
    
    // MARK: - Kontrol Layar Terintegrasi (Embedded Display)
    
    public func toggleScrcpyControl() {
        toggleDisplay()
    }
    
    public func toggleDisplay() {
        let isRunning = !runShell("pgrep -f 'UniversalADBControlDisplay'").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isRunning {
            stopDisplay()
        } else {
            startDisplay()
        }
    }
    
    public func startDisplay() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var target = self.preferredDevice.isEmpty ? (self.adbDevices.first?.serial ?? "") : self.preferredDevice
            
            if target.isEmpty {
                let output = self.runShell("\(self.adbPath) devices")
                for line in output.components(separatedBy: .newlines) {
                    let parts = line.split(separator: "\t", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                    if parts.count == 2 && parts[1] == "device" {
                        target = parts[0]
                        break
                    }
                }
            }
            
            guard !target.isEmpty else {
                DispatchQueue.main.async {
                    self.notify(message: "Tidak ada perangkat terhubung untuk dikontrol")
                }
                return
            }
            
            // Sembunyikan keyboard virtual Android
            _ = self.runShell("\(self.adbPath) -s \(target) shell settings put secure show_ime_with_hard_keyboard 0")
            
            let helperBin = ("~/.universal-adb-control/helpers/UniversalADBControlDisplay.app/Contents/MacOS/UniversalADBControlDisplay" as NSString).expandingTildeInPath
            let exec = FileManager.default.isExecutableFile(atPath: helperBin) ? helperBin : "UniversalADBControlDisplay"
            
            let myPid = ProcessInfo.processInfo.processIdentifier
            let dylibPath = ("~/.universal-adb-control/helpers/libUniversalControlFrame.dylib" as NSString).expandingTildeInPath
            let dyldExport = FileManager.default.fileExists(atPath: dylibPath) ? "export DYLD_INSERT_LIBRARIES=\"\(dylibPath)\"; " : ""
            
            let envVars = "export SDL_MAC_BACKGROUND_APP=1; export UAC_PARENT_PID=\(myPid); export UAC_OFFSET_X=\(self.hostOffsetX); export UAC_OFFSET_Y=\(self.hostOffsetY); export UAC_WIDTH=\(self.hostWidth); export UAC_HEIGHT=\(self.hostHeight); \(dyldExport)"
            
            let args = "-s \(target) --window-width=\(Int(self.hostWidth)) --window-height=\(Int(self.hostHeight)) --stay-awake --shortcut-mod=rctrl --no-audio --video-codec=\(self.videoCodec) --video-bit-rate=\(self.videoBitrate) --max-size=\(self.maxSize) --max-fps=\(self.maxFps) --video-buffer=\(self.videoBufferMs) --keyboard=uhid --mouse=uhid --window-title=\"Universal ADB Control\""
            
            _ = self.runShell("\(envVars) nohup \"\(exec)\" \(args) > /dev/null 2>&1 &")
            
            DispatchQueue.main.async {
                self.isScrcpyActive = true
                self.notify(message: "Layar Android menyatu dalam aplikasi. Tekan ⌘⌥T untuk mengontrol langsung.")
                self.refreshStatus()
            }
        }
    }
    
    public func stopDisplay() {
        _ = runShell("pkill -f 'UniversalADBControlDisplay'")
        DispatchQueue.main.async {
            self.isScrcpyActive = false
            self.notify(message: "Layar kontrol Android dihentikan.")
            self.refreshStatus()
        }
    }
    
    // MARK: - Navigasi Hardware Android (ADB Key Events)
    
    public func sendKeyevent(_ keyCode: Int) {
        let target = preferredDevice.isEmpty ? (adbDevices.first?.serial ?? "") : preferredDevice
        guard !target.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.runShell("\(self.adbPath) -s \(target) shell input keyevent \(keyCode)")
        }
    }
    
    public func sendBack() { sendKeyevent(4) }
    public func sendHome() { sendKeyevent(3) }
    public func sendRecents() { sendKeyevent(187) }
    public func sendPower() { sendKeyevent(26) }
    public func sendVolumeUp() { sendKeyevent(24) }
    public func sendVolumeDown() { sendKeyevent(25) }
    
    public func connectWifi(ip: String, port: String) {
        guard !ip.isEmpty else { return }
        let p = port.isEmpty ? "5555" : port
        let res = runShell("\(adbPath) connect \(ip):\(p)").trimmingCharacters(in: .whitespacesAndNewlines)
        notify(message: res)
        refreshDevices()
    }
    
    public func disconnectWifi(serial: String) {
        let res = runShell("\(adbPath) disconnect \(serial)").trimmingCharacters(in: .whitespacesAndNewlines)
        notify(message: res)
        refreshDevices()
    }
    
    public func notify(message: String) {
        self.alertMessage = message
        self.showAlert = true
    }
    
    private func runShell(_ command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "export PATH=/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH; " + command]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "Error executing shell: \(error.localizedDescription)"
        }
    }
}
