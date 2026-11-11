import Foundation
import Cocoa
import Carbon

public final class ControlManager {
    public static let shared = ControlManager()
    
    private var hotKeyRef: EventHotKeyRef?
    private var isLaunching = false
    private var isControlling = false
    private var savedMousePos: CGPoint?
    private var lastFrontmostApp: NSRunningApplication?
    
    private let scrcpyBin: String
    private let adbBin: String
    
    private init() {
        let homebrewScrcpy = "/opt/homebrew/bin/scrcpy"
        let usrLocalScrcpy = "/usr/local/bin/scrcpy"
        if FileManager.default.fileExists(atPath: homebrewScrcpy) {
            scrcpyBin = homebrewScrcpy
        } else if FileManager.default.fileExists(atPath: usrLocalScrcpy) {
            scrcpyBin = usrLocalScrcpy
        } else {
            scrcpyBin = "scrcpy"
        }
        
        let homebrewAdb = "/opt/homebrew/bin/adb"
        let usrLocalAdb = "/usr/local/bin/adb"
        if FileManager.default.fileExists(atPath: homebrewAdb) {
            adbBin = homebrewAdb
        } else if FileManager.default.fileExists(atPath: usrLocalAdb) {
            adbBin = usrLocalAdb
        } else {
            adbBin = "adb"
        }
    }
    
    // Membungkus scrcpy ke dalam App Bundle helper mandiri berstatus LSUIElement
    // sehingga scrcpy TIDAK PERNAH muncul sebagai aplikasi mandiri di Dock / App Switcher
    public static func ensureDisplayHelperBundle(scrcpyBin: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let helperDir = home.appendingPathComponent(".universal-adb-control/helpers/UniversalADBControlDisplay.app", isDirectory: true)
        let macosDir = helperDir.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let execPath = macosDir.appendingPathComponent("UniversalADBControlDisplay").path
        let plistPath = helperDir.appendingPathComponent("Contents/Info.plist").path
        
        let fm = FileManager.default
        try? fm.createDirectory(at: macosDir, withIntermediateDirectories: true)
        
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleExecutable</key>
            <string>UniversalADBControlDisplay</string>
            <key>CFBundleIdentifier</key>
            <string>com.universal.adb.control.display</string>
            <key>CFBundleName</key>
            <string>Universal ADB Control</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>LSUIElement</key>
            <true/>
            <key>NSHighResolutionCapable</key>
            <true/>
        </dict>
        </plist>
        """
        try? plistContent.write(toFile: plistPath, atomically: true, encoding: .utf8)
        
        if !fm.fileExists(atPath: execPath) {
            // Salin binary helper jika tersedia dari bundle atau bin
            let bundleHelper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/UniversalADBControlDisplay.app/Contents/MacOS/UniversalADBControlDisplay").path
            if fm.isExecutableFile(atPath: bundleHelper) {
                try? fm.copyItem(atPath: bundleHelper, toPath: execPath)
            } else {
                try? fm.createSymbolicLink(atPath: execPath, withDestinationPath: scrcpyBin)
            }
        }
        
        return execPath
    }
    
    private var displayExecutable: String {
        return ControlManager.ensureDisplayHelperBundle(scrcpyBin: scrcpyBin)
    }
    
    public func registerHotKey() {
        var gMyHotKeyID = EventHotKeyID()
        gMyHotKeyID.signature = OSType(0x55414442) // "UADB"
        gMyHotKeyID.id = UInt32(100)
        
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)
        
        let installErr = InstallEventHandler(GetEventDispatcherTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            Logger.shared.log("HotKey Cmd+Option+T event triggered!")
            ControlManager.shared.handleHotKey()
            return noErr
        }, 1, &eventType, nil, nil)
        
        // kVK_ANSI_T = 0x11 (17) -> Cmd + Option + T
        let regErr = RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(cmdKey | optionKey), gMyHotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        if regErr == noErr && installErr == noErr {
            Logger.shared.log("HotKey Cmd+Option+T registered successfully.")
        } else {
            Logger.shared.log("Failed to register HotKey Cmd+Option+T (installErr: \(installErr), regErr: \(regErr))")
        }
    }
    
    public func handleHotKey() {
        DispatchQueue.main.async { [weak self] in
            self?.toggleControl()
        }
    }
    
    public func showNotification(title: String, message: String) {
        let appleScript = "display notification \"\(message)\" with title \"\(title)\""
        executeAppleScript(appleScript)
    }
    
    private func disableOnScreenKeyboard(serial: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: adbBin)
        p.arguments = ["-s", serial, "shell", "settings put secure show_ime_with_hard_keyboard 0"]
        try? p.run()
        p.waitUntilExit()
        Logger.shared.log("Disabled on-screen keyboard for device: \(serial)")
    }
    
    private func executeAppleScript(_ source: String) {
        if let script = NSAppleScript(source: source) {
            var errorInfo: NSDictionary?
            script.executeAndReturnError(&errorInfo)
        }
    }
    
    // MARK: - Mode terintegrasi (layar HP menempel di jendela GUI)

    private static let guiBundleId = "com.universal.adb.control.gui"

    private var isGuiRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: ControlManager.guiBundleId).isEmpty
    }

    private func embeddedHelperPid() -> pid_t? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", "UniversalADBControlDisplay.app/Contents/MacOS"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        return out.split(separator: "\n").compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }.first
    }

    private func helperWindowCenter(pid: pid_t) -> CGPoint? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in list where (w[kCGWindowOwnerPID as String] as? pid_t) == pid {
            if let dict = w[kCGWindowBounds as String] as? NSDictionary,
               let rect = CGRect(dictionaryRepresentation: dict), rect.width > 100 {
                return CGPoint(x: rect.midX, y: rect.midY)
            }
        }
        return nil
    }

    private func rememberMacContext() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != ControlManager.guiBundleId,
           front?.processIdentifier != embeddedHelperPid() {
            lastFrontmostApp = front
        }
        savedMousePos = CGEvent(source: nil)?.location
    }

    private func focusEmbedded(pid: pid_t) {
        executeAppleScript("""
        tell application "System Events"
            set frontmost of (first process whose bundle identifier is "\(ControlManager.guiBundleId)") to true
            set frontmost of (first process whose unix id is \(pid)) to true
        end tell
        """)
        // Pindahkan kursor ke tengah layar HP agar mouse langsung mengontrol Android
        if let center = helperWindowCenter(pid: pid) {
            CGWarpMouseCursorPosition(center)
        }
        isControlling = true
        Logger.shared.log("Control switched to embedded Android screen.")
    }

    private func returnToMac() {
        isControlling = false
        if let pos = savedMousePos {
            CGWarpMouseCursorPosition(pos)
        }
        if let prev = lastFrontmostApp, !prev.isTerminated {
            executeAppleScript("""
            tell application "System Events" to set frontmost of (first process whose unix id is \(prev.processIdentifier)) to true
            """)
        }
        Logger.shared.log("Control switched back to Mac.")
    }

    private func toggleEmbedded() {
        if let pid = embeddedHelperPid() {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                returnToMac()
            } else {
                rememberMacContext()
                if let serial = getConnectedAdbDevices().first(where: { $0.state == "device" })?.serial {
                    disableOnScreenKeyboard(serial: serial)
                }
                focusEmbedded(pid: pid)
            }
            return
        }

        // Layar belum aktif: minta GUI menyalakannya, lalu fokuskan
        rememberMacContext()
        isLaunching = true
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.universal.adb.control.start"), object: nil, userInfo: nil, deliverImmediately: true)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var found: pid_t?
            for _ in 0..<40 {
                Thread.sleep(forTimeInterval: 0.2)
                if let pid = self.embeddedHelperPid(), self.helperWindowCenter(pid: pid) != nil {
                    found = pid
                    break
                }
            }
            DispatchQueue.main.async {
                self.isLaunching = false
                if let pid = found { self.focusEmbedded(pid: pid) }
            }
        }
    }

    public func toggleControl() {
        if isLaunching { return }
        if isGuiRunning {
            toggleEmbedded()
        } else {
            launchGuiAndStart()
        }
    }

    private func launchGuiAndStart() {
        if isLaunching { return }
        isLaunching = true

        let targetUrl: URL? = {
            let appUrl = URL(fileURLWithPath: "/Applications/Universal ADB Control.app")
            if FileManager.default.fileExists(atPath: appUrl.path) { return appUrl }
            let homeAppUrl = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/code/adb-control/bin/Universal ADB Control.app")
            if FileManager.default.fileExists(atPath: homeAppUrl.path) { return homeAppUrl }
            return nil
        }()

        let launchBlock = { [weak self] in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                for _ in 0..<40 {
                    Thread.sleep(forTimeInterval: 0.2)
                    if self.isGuiRunning {
                        DispatchQueue.main.async {
                            self.isLaunching = false
                            self.toggleEmbedded()
                        }
                        return
                    }
                }
                DispatchQueue.main.async {
                    self.isLaunching = false
                }
            }
        }

        if let url = targetUrl {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, err in
                if err != nil {
                    _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/open"), arguments: ["-a", "Universal ADB Control"])
                }
                launchBlock()
            }
        } else {
            _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/open"), arguments: ["-a", "Universal ADB Control"])
            launchBlock()
        }
    }

    private func getConnectedAdbDevices() -> [(serial: String, state: String)] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: adbBin)
        p.arguments = ["devices"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()

        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                var list: [(serial: String, state: String)] = []
                for line in output.components(separatedBy: .newlines) {
                    let parts = line.split(separator: "\t", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                    if parts.count == 2 && parts[0] != "List of devices attached" {
                        list.append((serial: parts[0], state: parts[1]))
                    }
                }
                return list
            }
        } catch {
            Logger.shared.log("Error running adb devices: \(error)")
        }
        return []
    }
}
