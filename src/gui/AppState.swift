import Foundation
import Combine
import Cocoa
import SwiftUI

public struct AdbDeviceItem: Identifiable, Hashable {
    public var id: String { serial }
    public let serial: String
    public let state: String
    public let model: String
    public let isWifi: Bool

    public var isReady: Bool { state == "device" }
    public var isUnauthorized: Bool { state == "unauthorized" }
    public var isOffline: Bool { state == "offline" }

    public var displayName: String {
        let clean = model.replacingOccurrences(of: "_", with: " ")
        if clean.isEmpty || clean == "Android" {
            return isWifi ? "Perangkat Wi-Fi" : "Perangkat USB"
        }
        return clean
    }

    public var connectionType: String {
        isWifi ? "Wi-Fi" : "USB"
    }

    public var connectionIcon: String {
        isWifi ? "wifi" : "cable.connector.horizontal"
    }
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
    @Published public var isLandscape: Bool = false
    @Published public var screenAspectRatio: CGFloat = 9.0 / 20.0
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
            if self.activeDevice != nil {
                self.checkRotation()
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
        startDisplay(retryCount: 3)
    }

    public func startDisplay(retryCount: Int) {
        guard !isStreaming else { return }
        guard let device = activeDevice else {
            if retryCount > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.startDisplay(retryCount: retryCount - 1)
                }
            } else {
                showToast("Belum ada perangkat")
            }
            return
        }
        guard FileManager.default.isExecutableFile(atPath: helperBin) else {
            showToast("Jalankan bundle_app.sh dulu")
            return
        }
        isStreaming = true
        checkRotation()
        writeHostRect()

        let serial = device.serial
        let rect = hostRect
        let isWifi = device.isWifi
        let codec = isWifi ? "h264" : videoCodec
        let buffer = isWifi ? "45" : videoBufferMs
        let maxBitrate = isWifi ? (quality == .tajam ? "4M" : quality.bitrate) : quality.bitrate
        let size = isWifi ? (quality == .tajam ? "1280" : quality.maxSize) : quality.maxSize

        let args = [
            "-s", serial,
            "--window-borderless",
            "--window-width=\(Int(rect.width))",
            "--window-height=\(Int(rect.height))",
            "--stay-awake",
            "--shortcut-mod=rctrl",
            "--no-audio",
            "--video-codec=\(codec)",
            "--video-bit-rate=\(maxBitrate)",
            "--max-size=\(size)",
            "--max-fps=\(maxFps)",
            "--video-buffer=\(buffer)",
            "--keyboard=sdk",
            "--mouse=sdk",
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

    // MARK: - Rotasi layar (Landscape vs Portrait)

    public func checkRotation() {
        guard let serial = activeDevice?.serial else { return }
        let adb = adbPath
        worker.async { [weak self] in
            guard let self = self else { return }
            var isLand = false
            var ratio: CGFloat = 9.0 / 20.0
            var matched = false

            // 1. Cek langsung dari mCurrentDisplayRect (paling akurat untuk semua Android & vendor)
            let dispOutput = self.runShell("\(adb) -s \(serial) shell \"dumpsys display | grep -m 1 'mCurrentDisplayRect'\"")
            if let regex = try? NSRegularExpression(pattern: "-\\s*([0-9]+),\\s*([0-9]+)\\)", options: []) {
                let nsStr = dispOutput as NSString
                if let match = regex.firstMatch(in: dispOutput, options: [], range: NSRange(location: 0, length: nsStr.length)) {
                    let wStr = nsStr.substring(with: match.range(at: 1))
                    let hStr = nsStr.substring(with: match.range(at: 2))
                    if let w = Double(wStr), let h = Double(hStr), w > 0, h > 0 {
                        isLand = w > h
                        ratio = CGFloat(w / h)
                        matched = true
                    }
                }
            }

            // 2. Fallback jika mCurrentDisplayRect tidak ditemukan
            if !matched {
                let rotOutput = self.runShell("\(adb) -s \(serial) shell \"cmd window user-rotation || dumpsys window | grep -m 1 'mCurrentRotation'\"")
                if rotOutput.contains("ROTATION_90") || rotOutput.contains("ROTATION_270") || rotOutput.contains("lock 1") || rotOutput.contains("lock 3") {
                    isLand = true
                    ratio = 20.0 / 9.0
                } else {
                    isLand = false
                    ratio = 9.0 / 20.0
                }
            }

            DispatchQueue.main.async {
                if self.isLandscape != isLand || abs(self.screenAspectRatio - ratio) > 0.02 {
                    withAnimation(.smooth(duration: 0.35)) {
                        self.isLandscape = isLand
                        self.screenAspectRatio = ratio
                    }
                    self.adaptWindowForOrientation(isLandscape: isLand)
                }
            }
        }
    }

    public func toggleRotation() {
        guard let serial = activeDevice?.serial else { return }
        let adb = adbPath
        let nextLand = !isLandscape
        worker.async { [weak self] in
            guard let self = self else { return }
            _ = self.runShell("\(adb) -s \(serial) shell \"cmd window user-rotation lock \(nextLand ? 1 : 0) || (settings put system accelerometer_rotation 0 && settings put system user_rotation \(nextLand ? 1 : 0))\"")
            Thread.sleep(forTimeInterval: 0.3)
            self.checkRotation()
        }
    }

    private func adaptWindowForOrientation(isLandscape: Bool) {
        guard let window = NSApp.windows.first(where: { $0.title == "Universal ADB Control" || $0.canBecomeMain }) else { return }
        if isLandscape {
            window.minSize = NSSize(width: 480, height: 320)
        } else {
            window.minSize = NSSize(width: 320, height: 480)
        }
        var f = window.frame
        if isLandscape && f.width < f.height {
            let targetW = max(f.height * 1.25, 720)
            let targetH = max(f.width * 0.75, 420)
            f.origin.x -= (targetW - f.width) / 2
            f.origin.y -= (targetH - f.height) / 2
            f.size.width = targetW
            f.size.height = targetH
            window.setFrame(f, display: true, animate: true)
        } else if !isLandscape && f.width > f.height {
            let targetW = max(f.height * 0.60, 420)
            let targetH = max(f.width * 0.95, 740)
            f.origin.x -= (targetW - f.width) / 2
            f.origin.y -= (targetH - f.height) / 2
            f.size.width = targetW
            f.size.height = targetH
            window.setFrame(f, display: true, animate: true)
        }
    }

    // MARK: - Sinkron clipboard (daemon)

    public func setSync(_ on: Bool) {
        isSyncOn = on
        worker.async { [weak self] in
            _ = self?.runShell("universal-adb-control \(on ? "start" : "stop")")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self?.refresh() }
        }
    }

    // MARK: - Wi-Fi & Pairing

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

    public func pairAndConnect(pairingAddress: String, code: String) {
        let pairAddr = pairingAddress.trimmingCharacters(in: .whitespaces)
        let pin = code.trimmingCharacters(in: .whitespaces)
        guard !pairAddr.isEmpty, !pin.isEmpty else { return }
        let adb = adbPath
        worker.async { [weak self] in
            guard let self = self else { return }
            let pairOutput = self.runShell("\(adb) pair \(pairAddr) \(pin)")
            if pairOutput.contains("Successfully paired to") {
                Thread.sleep(forTimeInterval: 0.5)
                let connOutput = self.runShell("\(adb) connect \(pairAddr)").lowercased()
                DispatchQueue.main.async {
                    if connOutput.contains("connected to") && !connOutput.contains("cannot") {
                        self.selectDevice(pairAddr)
                    } else {
                        self.showToast("Berhasil dipasangkan")
                    }
                    self.refresh()
                }
            } else {
                DispatchQueue.main.async {
                    self.showToast("Gagal memasangkan")
                    self.refresh()
                }
            }
        }
    }

    public func enableTcpip(serial: String) {
        let adb = adbPath
        showToast("Mengaktifkan mode Wi-Fi...")
        worker.async { [weak self] in
            guard let self = self else { return }
            let res = self.runShell("\(adb) -s \(serial) tcpip 5555")
            let ipCmd = "\(adb) -s \(serial) shell ip -f inet addr show wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1"
            let ip = self.runShell(ipCmd).trimmingCharacters(in: .whitespacesAndNewlines)

            DispatchQueue.main.async {
                if res.contains("restarting in TCP mode") {
                    if !ip.isEmpty {
                        self.showToast("Mode Wi-Fi aktif. Menghubungkan ke \(ip):5555...")
                        self.worker.async {
                            Thread.sleep(forTimeInterval: 1.0)
                            _ = self.runShell("\(adb) connect \(ip):5555")
                            DispatchQueue.main.async {
                                self.showToast("Terhubung via Wi-Fi: \(ip):5555")
                                self.refresh()
                            }
                        }
                    } else {
                        self.showToast("Mode Wi-Fi aktif (Port 5555). Cabut USB & hubungkan via IP")
                    }
                } else {
                    let msg = res.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.showToast(msg.isEmpty ? "Gagal mengaktifkan mode Wi-Fi" : msg)
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
