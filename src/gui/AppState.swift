import Foundation
import Combine
import Cocoa

public struct AdbDeviceItem: Identifiable, Hashable {
    public var id: String { serial }
    public let serial: String
    public let state: String
    public let model: String
    public let isWifi: Bool

    public var isReady: Bool { state == "device" }
    public var displayName: String { model.replacingOccurrences(of: "_", with: "-") }
}

// Preset kualitas streaming (menyembunyikan angka bitrate/fps/codec dari pengguna)
public enum StreamQuality: String, CaseIterable, Identifiable {
    case hemat, seimbang, tajam

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .hemat: return "Hemat"
        case .seimbang: return "Seimbang"
        case .tajam: return "Tajam"
        }
    }
    var bitrate: String {
        switch self {
        case .hemat: return "2M"
        case .seimbang: return "3M"
        case .tajam: return "6M"
        }
    }
    var maxSize: String {
        switch self {
        case .hemat: return "1024"
        case .seimbang: return "1280"
        case .tajam: return "1600"
        }
    }
    static func from(bitrate: String) -> StreamQuality {
        switch bitrate.uppercased() {
        case "2M": return .hemat
        case "6M": return .tajam
        default: return .seimbang
        }
    }
}

public final class AppState: ObservableObject {
    @Published public var devices: [AdbDeviceItem] = []
    @Published public var selectedSerial: String = ""
    @Published public var isStreaming = false
    @Published public var isSyncOn = false
    @Published public var quality: StreamQuality = .seimbang
    @Published public var toast: String? = nil
    // Saat popover terbuka, layar HP disembunyikan sementara agar tidak menutupi popover
    @Published public var overlayOpen = false { didSet { writeHostRect() } }

    // Konfigurasi lanjutan (tetap kompatibel dengan config.conf milik CLI)
    private var adbPath = "/opt/homebrew/bin/adb"
    private var syncIntervalMs = "300"
    private var maxFps = "60"
    private var videoBufferMs = "15"
    private var videoCodec = "h265"

    // Geometri layar HP di dalam jendela (koordinat window, origin kiri bawah)
    private var hostRect = NSRect(x: 76, y: 92, width: 288, height: 640)
    private var hostRadius: CGFloat = 38

    private var displayProcess: Process?
    private var toastWork: DispatchWorkItem?
    private var timer: Timer?
    private let worker = DispatchQueue(label: "uac.worker", qos: .userInitiated)
    private let confPath = ("~/.universal-adb-control/config.conf" as NSString).expandingTildeInPath
    private let hostRectPath = ("~/.universal-adb-control/host_rect.json" as NSString).expandingTildeInPath
    private let helperBin = ("~/.universal-adb-control/helpers/UniversalADBControlDisplay.app/Contents/MacOS/UniversalADBControlDisplay" as NSString).expandingTildeInPath

    public var activeDevice: AdbDeviceItem? {
        devices.first { $0.serial == selectedSerial && $0.isReady } ?? devices.first { $0.isReady }
    }

    public init() {
        loadConfig()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Konfigurasi

    private func loadConfig() {
        guard let content = try? String(contentsOfFile: confPath, encoding: .utf8) else { return }
        var bitrate = "3M"
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "ADB": adbPath = parts[1]
            case "DEVICE": selectedSerial = parts[1]
            case "SYNC_INTERVAL_MS": syncIntervalMs = parts[1]
            case "VIDEO_BITRATE": bitrate = parts[1]
            case "MAX_FPS": maxFps = parts[1]
            case "VIDEO_BUFFER_MS": videoBufferMs = parts[1]
            case "VIDEO_CODEC": videoCodec = parts[1]
            default: break
            }
        }
        quality = StreamQuality.from(bitrate: bitrate)
    }

    private func saveConfig() {
        let content = """
        # Universal ADB Control Configuration
        ADB=\(adbPath)
        DEVICE=\(selectedSerial)
        SYNC_INTERVAL_MS=\(syncIntervalMs)
        VIDEO_BITRATE=\(quality.bitrate)
        MAX_SIZE=\(quality.maxSize)
        MAX_FPS=\(maxFps)
        VIDEO_BUFFER_MS=\(videoBufferMs)
        VIDEO_CODEC=\(videoCodec)
        """
        try? content.write(toFile: confPath, atomically: true, encoding: .utf8)
    }

    public func setQuality(_ q: StreamQuality) {
        guard q != quality else { return }
        quality = q
        saveConfig()
        if isStreaming { restartDisplay() }
    }

    public func selectDevice(_ serial: String) {
        guard serial != selectedSerial else { return }
        selectedSerial = serial
        saveConfig()
        if isStreaming { restartDisplay() }
    }

    // MARK: - Status (berjalan di background agar UI tidak tersendat)

    public func refresh() {
        let adb = adbPath
        worker.async { [weak self] in
            guard let self = self else { return }
            let devs = self.parseDevices(self.runShell("\(adb) devices -l"))
            let sync = !self.runShell("pgrep -f universal-adb-control-daemon").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            DispatchQueue.main.async {
                if self.devices != devs { self.devices = devs }
                if self.isSyncOn != sync { self.isSyncOn = sync }
            }
        }
    }

    private func parseDevices(_ output: String) -> [AdbDeviceItem] {
        var items: [AdbDeviceItem] = []
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("List of devices") || trimmed.hasPrefix("*") { continue }
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2 else { continue }
            let model = parts.first { $0.hasPrefix("model:") }?.replacingOccurrences(of: "model:", with: "") ?? "Android"
            let serial = parts[0]
            items.append(AdbDeviceItem(serial: serial, state: parts[1], model: model,
                                       isWifi: serial.contains(":") || serial.contains("._tcp")))
        }
        return items
    }

    // MARK: - Geometri layar terintegrasi

    public func updateHostGeometry(rect: NSRect, radius: CGFloat) {
        guard rect.width > 50, rect.height > 50 else { return }
        if rect.integral == hostRect.integral && abs(radius - hostRadius) < 0.5 { return }
        hostRect = rect
        hostRadius = radius
        writeHostRect()
    }

    private func writeHostRect() {
        let json = "{\"offsetX\": \(hostRect.origin.x), \"offsetY\": \(hostRect.origin.y), \"width\": \(hostRect.width), \"height\": \(hostRect.height), \"radius\": \(hostRadius), \"hidden\": \(overlayOpen)}"
        try? json.write(toFile: hostRectPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Layar Android

    public func toggleDisplay() {
        isStreaming ? stopDisplay() : startDisplay()
    }

    public func startDisplay() {
        guard !isStreaming else { return }
        guard let device = activeDevice else {
            showToast("Belum ada perangkat")
            return
        }
        guard FileManager.default.isExecutableFile(atPath: helperBin) else {
            showToast("Jalankan bundle_app.sh dulu")
            return
        }
        isStreaming = true
        writeHostRect()

        let serial = device.serial
        let rect = hostRect
        let args = [
            "-s", serial,
            "--window-borderless",
            "--window-width=\(Int(rect.width))",
            "--window-height=\(Int(rect.height))",
            "--stay-awake",
            "--shortcut-mod=rctrl",
            "--no-audio",
            "--video-codec=\(videoCodec)",
            "--video-bit-rate=\(quality.bitrate)",
            "--max-size=\(quality.maxSize)",
            "--max-fps=\(maxFps)",
            "--video-buffer=\(videoBufferMs)",
            "--keyboard=uhid",
            "--mouse=uhid",
            "--window-title=Universal ADB Control"
        ]
        let adb = adbPath
        let bin = helperBin

        worker.async { [weak self] in
            guard let self = self else { return }
            // Sembunyikan keyboard virtual Android saat keyboard fisik aktif
            _ = self.runShell("\(adb) -s \(serial) shell settings put secure show_ime_with_hard_keyboard 0")

            let p = Process()
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = args
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            env["UAC_PARENT_PID"] = String(ProcessInfo.processInfo.processIdentifier)
            p.environment = env
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { [weak self] proc in
                DispatchQueue.main.async {
                    guard let self = self, self.displayProcess === proc else { return }
                    self.displayProcess = nil
                    self.isStreaming = false
                    if proc.terminationStatus != 0 && proc.terminationReason == .exit {
                        self.showToast("Koneksi layar terputus")
                    }
                }
            }
            do {
                try p.run()
                DispatchQueue.main.async { self.displayProcess = p }
            } catch {
                DispatchQueue.main.async {
                    self.isStreaming = false
                    self.showToast("Gagal membuka layar")
                }
            }
        }
    }

    public func stopDisplay() {
        let p = displayProcess
        displayProcess = nil
        p?.terminate()
        _ = runShell("pkill -f 'UniversalADBControlDisplay.app/Contents/MacOS'")
        isStreaming = false
    }

    private func restartDisplay() {
        stopDisplay()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.startDisplay()
        }
    }

    // MARK: - Tombol fisik Android

    private func sendKeyevent(_ code: Int) {
        guard let serial = activeDevice?.serial else { return }
        let adb = adbPath
        worker.async { [weak self] in
            _ = self?.runShell("\(adb) -s \(serial) shell input keyevent \(code)")
        }
    }

    public func sendBack() { sendKeyevent(4) }
    public func sendHome() { sendKeyevent(3) }
    public func sendRecents() { sendKeyevent(187) }
    public func sendPower() { sendKeyevent(26) }
    public func sendVolumeUp() { sendKeyevent(24) }
    public func sendVolumeDown() { sendKeyevent(25) }

    // MARK: - Sinkron clipboard (daemon)

    public func setSync(_ on: Bool) {
        isSyncOn = on
        worker.async { [weak self] in
            _ = self?.runShell("universal-adb-control \(on ? "start" : "stop")")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self?.refresh() }
        }
    }

    // MARK: - Wi-Fi

    public func connectWifi(_ address: String) {
        let addr = address.trimmingCharacters(in: .whitespaces)
        guard !addr.isEmpty else { return }
        let target = addr.contains(":") ? addr : "\(addr):5555"
        let adb = adbPath
        worker.async { [weak self] in
            guard let self = self else { return }
            let res = self.runShell("\(adb) connect \(target)").lowercased()
            DispatchQueue.main.async {
                if res.contains("connected to") && !res.contains("cannot") {
                    self.selectDevice(target)
                } else {
                    self.showToast("Gagal terhubung")
                }
                self.refresh()
            }
        }
    }

    public func disconnect(_ serial: String) {
        if serial == activeDevice?.serial && isStreaming { stopDisplay() }
        let adb = adbPath
        worker.async { [weak self] in
            _ = self?.runShell("\(adb) disconnect \(serial)")
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    // MARK: - Toast singkat (pengganti dialog alert)

    public func showToast(_ message: String) {
        toastWork?.cancel()
        toast = message
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }

    @discardableResult
    private func runShell(_ command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "export PATH=/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH; " + command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
