import Foundation
import Network

public struct AdbDeviceInfo {
    public let serial: String
    public let state: String
    public let model: String?
}

public final class AdbTransport {
    private let config: DaemonConfig
    private var activeProcess: Process?
    private let lock = NSLock()
    private var _currentDeviceSerial: String?
    public var currentDeviceSerial: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _currentDeviceSerial
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _currentDeviceSerial = newValue
        }
    }

    private var connection: NWConnection?
    private let netQueue = DispatchQueue(label: "com.universal.clipboard.net", qos: .userInitiated)
    private let tcpPort: UInt16 = 28888

    public var onMessageReceived: ((ClipboardMessage) -> Void)?
    public var onDisconnected: (() -> Void)?

    public init(config: DaemonConfig) {
        self.config = config
    }

    public func discoverDevices() -> [AdbDeviceInfo] {
        let task = Process()
        task.launchPath = config.adbPath
        task.arguments = ["devices", "-l"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }

            var list: [AdbDeviceInfo] = []
            for line in output.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("List") { continue }
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 2 {
                    let serial = parts[0]
                    let state = parts[1]
                    var model: String? = nil
                    for p in parts {
                        if p.hasPrefix("model:") {
                            model = p.replacingOccurrences(of: "model:", with: "")
                        }
                    }
                    list.append(AdbDeviceInfo(serial: serial, state: state, model: model))
                }
            }
            return list
        } catch {
            return []
        }
    }

    private func loadIgnoredDevices() -> Set<String> {
        let path = ("~/.universal-adb-control/ignored_devices.txt" as NSString).expandingTildeInPath
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        let entries = content.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return Set(entries)
    }

    private func isIgnored(_ serial: String, ignored: Set<String>) -> Bool {
        if ignored.contains(serial) { return true }
        if serial.contains(":"), let host = serial.split(separator: ":").first.map(String.init) {
            if ignored.contains(host) { return true }
        }
        return false
    }

    private func autoConnectMdnsIfPossible(ignored: Set<String>) {
        let task = Process()
        task.launchPath = config.adbPath
        task.arguments = ["mdns", "services"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return }

        for line in output.components(separatedBy: .newlines) {
            let cols = line.split(whereSeparator: { $0.isWhitespace })
            if cols.count >= 3 {
                let svcName = String(cols[0])
                let svc = String(cols[1])
                let addr = String(cols[2])
                if svc.contains("_adb-tls-connect") && addr.contains(":") {
                    if isIgnored(addr, ignored: ignored) || ignored.contains(where: { $0.contains(svcName) }) {
                        continue
                    }
                    let connTask = Process()
                    connTask.launchPath = self.config.adbPath
                    connTask.arguments = ["connect", addr]
                    try? connTask.run()
                    connTask.waitUntilExit()
                    return
                }
            }
        }
    }

    public func selectTargetDevice() -> String? {
        let ignored = loadIgnoredDevices()
        var devices = discoverDevices().filter { $0.state == "device" && !isIgnored($0.serial, ignored: ignored) }
        if devices.isEmpty {
            autoConnectMdnsIfPossible(ignored: ignored)
            devices = discoverDevices().filter { $0.state == "device" && !isIgnored($0.serial, ignored: ignored) }
        }
        if devices.isEmpty { return nil }

        if let pref = config.preferredDevice, !pref.isEmpty {
            if let matched = devices.first(where: { $0.serial == pref }) {
                return matched.serial
            }
        }
        return devices.first?.serial
    }

    public func pushFile(localPath: String, remotePath: String, serial: String) -> Bool {
        let task = Process()
        task.launchPath = config.adbPath
        task.arguments = ["-s", serial, "push", localPath, remotePath]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    public func pullFile(remotePath: String, localPath: String, serial: String) -> Bool {
        let task = Process()
        task.launchPath = config.adbPath
        task.arguments = ["-s", serial, "pull", remotePath, localPath]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    public func startAgent(serial: String, dexLocalPath: String) -> Bool {
        stopAgent()
        currentDeviceSerial = serial

        // Ensure agent DEX is pushed
        let remoteDex = "/data/local/tmp/clipboard_agent.dex"
        if !pushFile(localPath: dexLocalPath, remotePath: remoteDex, serial: serial) {
            Logger.shared.log("Failed to push agent DEX to device \(serial)")
            return false
        }

        // Kill previous instances of AndroidClipboardAgent
        let killTask = Process()
        killTask.launchPath = config.adbPath
        killTask.arguments = ["-s", serial, "shell", "pkill -9 -f AndroidClipboardAgent; pkill -9 -f clipboard_agent.dex"]
        try? killTask.run()
        killTask.waitUntilExit()
        Thread.sleep(forTimeInterval: 0.2)

        // Sembunyikan on-screen keyboard saat physical/UHID keyboard aktif
        let imeTask = Process()
        imeTask.launchPath = config.adbPath
        imeTask.arguments = ["-s", serial, "shell", "settings put secure show_ime_with_hard_keyboard 0"]
        try? imeTask.run()
        imeTask.waitUntilExit()

        // Setup ADB port forwarding to Android TCP server
        let fwdTask = Process()
        fwdTask.launchPath = config.adbPath
        fwdTask.arguments = ["-s", serial, "forward", "tcp:\(tcpPort)", "tcp:\(tcpPort)"]
        try? fwdTask.run()
        fwdTask.waitUntilExit()

        // Launch agent background daemon on Android
        let task = Process()
        task.launchPath = config.adbPath
        task.arguments = [
            "-s", serial,
            "shell",
            "CLASSPATH=\(remoteDex) nohup app_process /data/local/tmp com.universal.clipboard.AndroidClipboardAgent >/dev/null 2>&1 &"
        ]
        try? task.run()
        task.waitUntilExit()

        // Give server socket 1.0s to bind
        Thread.sleep(forTimeInterval: 1.0)

        // Connect TCP client socket to forwarded port
        connectTcpSocket()
        return true
    }

    private func connectTcpSocket() {
        let host = NWEndpoint.Host("127.0.0.1")
        let port = NWEndpoint.Port(rawValue: tcpPort)!
        let conn = NWConnection(host: host, port: port, using: .tcp)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                Logger.shared.log("Direct TCP socket connected to Android agent (port \(self.tcpPort))")
                self.startReading()
            case .failed(let err):
                Logger.shared.log("TCP socket connection failed: \(err)")
                self.handleDisconnection()
            case .cancelled:
                Logger.shared.log("TCP socket connection cancelled")
            default:
                break
            }
        }

        conn.start(queue: netQueue)
    }

    private var incomingBuffer = Data()

    private func startReading() {
        guard let conn = connection else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                self.incomingBuffer.append(data)
                while let newlineIndex = self.incomingBuffer.firstIndex(of: 0x0A) {
                    let lineData = self.incomingBuffer.subdata(in: 0..<newlineIndex)
                    self.incomingBuffer.removeSubrange(0...newlineIndex)

                    if let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !line.isEmpty {
                        self.parseIncomingLine(line)
                    }
                }
            }

            if isComplete || error != nil {
                Logger.shared.log("TCP socket stream ended or error: \(String(describing: error))")
                self.handleDisconnection()
            } else {
                self.startReading()
            }
        }
    }

    public func sendMessage(_ msg: ClipboardMessage) {
        guard let data = try? JSONEncoder().encode(msg),
              let jsonStr = String(data: data, encoding: .utf8) else {
            Logger.shared.log("Error encoding message to JSON")
            return
        }
        guard let conn = connection else {
            Logger.shared.log("TCP connection is nil when trying to send message")
            return
        }

        let line = jsonStr + "\n"
        guard let lineData = line.data(using: .utf8) else { return }
        conn.send(content: lineData, completion: .contentProcessed { [weak self] err in
            if let err = err {
                Logger.shared.log("Error sending message over TCP: \(err)")
                self?.handleDisconnection()
            } else {
                Logger.shared.log("Sent message to Android over TCP: \(msg.type.rawValue)")
            }
        })
    }

    private func parseIncomingLine(_ line: String) {
        guard line.hasPrefix("{") && line.hasSuffix("}") else { return }
        guard let data = line.data(using: .utf8),
              let msg = try? JSONDecoder().decode(ClipboardMessage.self, from: data) else {
            return
        }
        onMessageReceived?(msg)
    }

    private func handleDisconnection() {
        connection?.cancel()
        connection = nil
        currentDeviceSerial = nil
        onDisconnected?()
    }

    public func stopAgent() {
        connection?.cancel()
        connection = nil
        activeProcess?.terminate()
        activeProcess = nil
        currentDeviceSerial = nil
    }
}
