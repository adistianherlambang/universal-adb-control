import Foundation
import AppKit

public final class ClipboardDaemon {
    private let config: DaemonConfig
    private let transport: AdbTransport
    private let pasteboardManager: PasteboardManager
    private let dexPath: String

    private var pollTimer: Timer?
    private var reconnectTimer: Timer?
    private var lastHandledHash: String = ""
    private var isSyncing: Bool = false

    public init(config: DaemonConfig, dexPath: String) {
        self.config = config
        self.transport = AdbTransport(config: config)
        self.pasteboardManager = PasteboardManager()
        self.dexPath = dexPath
    }

    public func start() {
        Logger.shared.log("Starting Universal Clipboard macOS Daemon...")
        DaemonState.shared.update(running: true)

        transport.onMessageReceived = { [weak self] msg in
            self?.handleIncomingAndroidMessage(msg)
        }

        transport.onDisconnected = { [weak self] in
            Logger.shared.log("Transport disconnected from Android")
            DaemonState.shared.update(running: true, connectedDevice: nil, error: "Disconnected")
            self?.scheduleReconnect()
        }

        connectToDevice()
        startPasteboardMonitoring()

        RunLoop.main.run()
    }

    private func connectToDevice() {
        guard let serial = transport.selectTargetDevice() else {
            Logger.shared.log("No authorized Android device found. Waiting for device...")
            DaemonState.shared.update(running: true, connectedDevice: nil, error: "No Android device")
            scheduleReconnect()
            return
        }

        Logger.shared.log("Found Android device: \(serial). Launching agent...")
        if transport.startAgent(serial: serial, dexLocalPath: dexPath) {
            Logger.shared.log("Agent started and connected to \(serial)")
            DaemonState.shared.update(running: true, connectedDevice: serial)
        } else {
            Logger.shared.log("Failed to start agent on \(serial)")
            DaemonState.shared.update(running: true, connectedDevice: nil, error: "Failed to start agent")
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.connectToDevice()
        }
    }

    private func startPasteboardMonitoring() {
        pollTimer?.invalidate()
        let interval = Double(config.syncIntervalMs) / 1000.0
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkMacPasteboard()
        }
    }

    private func checkMacPasteboard() {
        guard !isSyncing else { return }
        guard pasteboardManager.hasChange() else { return }
        guard let (content, hash) = pasteboardManager.getCurrentContent() else { return }

        if hash == lastHandledHash {
            return // Prevent loop
        }
        lastHandledHash = hash

        guard let serial = transport.currentDeviceSerial else {
            Logger.shared.log("Mac clipboard changed, but no Android device is currently connected")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        switch content {
        case .text(let plain, let html):
            Logger.shared.log("Syncing TEXT (Mac -> Android, length=\(plain.count), hash=\(String(hash.prefix(8))))")
            let msg = ClipboardMessage(
                type: .text,
                origin: "mac",
                hash: hash,
                text: plain,
                html: html
            )
            transport.sendMessage(msg)
            DaemonState.shared.update(running: true, connectedDevice: serial, contentType: "TEXT", direction: "Mac -> Android")

        case .image(let data, let mime, let filename):
            Logger.shared.log("Syncing IMAGE (Mac -> Android, size=\(data.count), mime=\(mime), hash=\(String(hash.prefix(8))))")
            let localTmp = config.storageDir.appendingPathComponent(filename)
            try? data.write(to: localTmp)

            let remotePath = "/sdcard/Download/UniversalClipboard/\(filename)"
            if transport.pushFile(localPath: localTmp.path, remotePath: remotePath, serial: serial) {
                let msg = ClipboardMessage(
                    type: .image,
                    origin: "mac",
                    hash: hash,
                    mime: mime,
                    remotePath: remotePath,
                    size: Int64(data.count)
                )
                transport.sendMessage(msg)
                DaemonState.shared.update(running: true, connectedDevice: serial, contentType: "IMAGE", direction: "Mac -> Android")
            } else {
                Logger.shared.log("Error pushing image to device")
            }

        case .files(let urls):
            Logger.shared.log("Syncing FILES (Mac -> Android, count=\(urls.count), hash=\(String(hash.prefix(8))))")
            var remoteList: [String] = []
            for url in urls {
                let remoteTarget = "/sdcard/Download/UniversalClipboard/\(url.lastPathComponent)"
                if transport.pushFile(localPath: url.path, remotePath: remoteTarget, serial: serial) {
                    remoteList.append(remoteTarget)
                }
            }
            if !remoteList.isEmpty {
                let msg = ClipboardMessage(
                    type: .files,
                    origin: "mac",
                    hash: hash,
                    remotePaths: remoteList,
                    count: remoteList.count
                )
                transport.sendMessage(msg)
                DaemonState.shared.update(running: true, connectedDevice: serial, contentType: "FILES", direction: "Mac -> Android")
            }

        case .none:
            break
        }
    }

    private func handleIncomingAndroidMessage(_ msg: ClipboardMessage) {
        guard let hash = msg.hash, hash != lastHandledHash else { return }
        lastHandledHash = hash

        guard let serial = transport.currentDeviceSerial else { return }

        isSyncing = true
        defer { isSyncing = false }

        switch msg.type {
        case .text:
            if let text = msg.text {
                Logger.shared.log("Received TEXT (Android -> Mac, length=\(text.count), hash=\(String(hash.prefix(8))))")
                pasteboardManager.writeText(plain: text, html: msg.html)
                DaemonState.shared.update(running: true, connectedDevice: serial, contentType: "TEXT", direction: "Android -> Mac")
            }

        case .image:
            if let remotePath = msg.remotePath {
                let fileName = URL(fileURLWithPath: remotePath).lastPathComponent
                let localFile = config.storageDir.appendingPathComponent(fileName)
                Logger.shared.log("Received IMAGE (Android -> Mac, pulling \(fileName)...)")

                if transport.pullFile(remotePath: remotePath, localPath: localFile.path, serial: serial) {
                    pasteboardManager.writeImage(fileUrl: localFile)
                    Logger.shared.log("Image updated in Mac pasteboard: \(localFile.path)")
                    DaemonState.shared.update(running: true, connectedDevice: serial, contentType: "IMAGE", direction: "Android -> Mac")
                } else {
                    Logger.shared.log("Failed to pull image from device: \(remotePath)")
                }
            }

        case .files:
            if let remotePaths = msg.remotePaths, !remotePaths.isEmpty {
                Logger.shared.log("Received FILES (Android -> Mac, pulling \(remotePaths.count) files...)")
                var localUrls: [URL] = []
                for rp in remotePaths {
                    let fn = URL(fileURLWithPath: rp).lastPathComponent
                    let lf = config.storageDir.appendingPathComponent(fn)
                    if transport.pullFile(remotePath: rp, localPath: lf.path, serial: serial) {
                        localUrls.append(lf)
                    }
                }
                if !localUrls.isEmpty {
                    pasteboardManager.writeFiles(urls: localUrls)
                    Logger.shared.log("Files updated in Mac pasteboard (\(localUrls.count) items)")
                    DaemonState.shared.update(running: true, connectedDevice: serial, contentType: "FILES", direction: "Android -> Mac")
                }
            }

        case .ping:
            transport.sendMessage(ClipboardMessage(type: .pong, status: "OK"))

        case .pong:
            break
        }
    }
}
