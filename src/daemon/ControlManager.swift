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
    
    private func getDisplayApp() -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        for app in apps {
            let bid = app.bundleIdentifier ?? ""
            let name = app.localizedName?.lowercased() ?? ""
            if bid == "com.universal.adb.control.display" ||
               bid == "org.freedesktop.scrcpy" ||
               name.contains("universaladbcontroldisplay") ||
               name.contains("scrcpy") {
                return app
            }
        }
        return nil
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
    
    public func toggleControl() {
        if isLaunching {
            showNotification(title: "Universal ADB Control", message: "Sedang menghubungkan ke perangkat...")
            return
        }
        
        let displayApp = getDisplayApp()
        let isRunning = (displayApp != nil && !(displayApp?.isTerminated ?? true))
        
        if isControlling && isRunning {
            // Mode kontrol sedang aktif -> Kembali ke Mac
            switchToMac()
        } else if isRunning {
            // Display sudah ada tapi sedang disembunyikan -> Buka kembali ke Android
            switchToAndroid()
        } else {
            // Belum berjalan -> Luncurkan baru
            launchDisplay()
        }
    }
    
    private func switchToMac() {
        isControlling = false
        
        if let app = getDisplayApp() {
            app.hide()
            let script = """
            tell application "System Events"
                set visible of (every process whose bundle identifier is "com.universal.adb.control.display" or name contains "UniversalADBControlDisplay" or name contains "scrcpy") to false
            end tell
            """
            executeAppleScript(script)
        }
        
        // Kembalikan posisi kursor mouse ke posisi sebelumnya di Mac
        if let pos = savedMousePos {
            CGDisplayMoveCursorToPoint(CGMainDisplayID(), pos)
        }
        
        // Fokuskan kembali aplikasi Mac yang tadi sedang dibuka
        if let prev = lastFrontmostApp, !prev.isTerminated {
            prev.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
        
        showNotification(title: "Universal ADB Control", message: "Kembali ke Mac (Mouse & Keyboard aktif di Mac)")
        Logger.shared.log("Control switched back to Mac.")
    }
    
    private func switchToAndroid() {
        guard let app = getDisplayApp(), !app.isTerminated else {
            launchDisplay()
            return
        }
        
        lastFrontmostApp = NSWorkspace.shared.frontmostApplication
        savedMousePos = CGEvent(source: nil)?.location
        
        // Pastikan keyboard virtual di Android disembunyikan saat hardware keyboard terhubung
        if let serial = getConnectedAdbDevices().first(where: { $0.state == "device" })?.serial {
            disableOnScreenKeyboard(serial: serial)
        }
        
        let script = """
        tell application "System Events"
            set visible of (every process whose bundle identifier is "com.universal.adb.control.display" or name contains "UniversalADBControlDisplay" or name contains "scrcpy") to true
            set frontmost of (first process whose bundle identifier is "com.universal.adb.control.display" or name contains "UniversalADBControlDisplay" or name contains "scrcpy") to true
        end tell
        """
        executeAppleScript(script)
        app.unhide()
        app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        
        isControlling = true
        showNotification(title: "Universal ADB Control", message: "Mengontrol Android (Mode Emulator, ⌘⌥T untuk kembali)")
        Logger.shared.log("Control switched to Android.")
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
    
    private func launchDisplay() {
        let devs = getConnectedAdbDevices()
        if devs.isEmpty {
            showNotification(title: "Universal ADB Control", message: "Tidak ada perangkat Android terhubung!")
            return
        }
        
        let validDevs = devs.filter { $0.state == "device" }
        if validDevs.isEmpty {
            let state = devs.first?.state ?? "unknown"
            showNotification(title: "Universal ADB Control", message: "Perangkat terdeteksi status: \(state)")
            return
        }
        
        let config = DaemonConfig.load()
        var targetSerial: String = validDevs[0].serial
        if let pref = config.preferredDevice, !pref.isEmpty {
            if validDevs.contains(where: { $0.serial == pref }) {
                targetSerial = pref
            }
        }
        
        isLaunching = true
        showNotification(title: "Universal ADB Control", message: "Menghubungkan (\(targetSerial))...")
        
        // Sembunyikan keyboard virtual (IME) di layar Android agar tidak menutupi tampilan
        disableOnScreenKeyboard(serial: targetSerial)
        
        lastFrontmostApp = NSWorkspace.shared.frontmostApplication
        savedMousePos = CGEvent(source: nil)?.location
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let p = Process()
            p.executableURL = URL(fileURLWithPath: self.displayExecutable)
            
            var env = ProcessInfo.processInfo.environment
            env["SDL_MAC_BACKGROUND_APP"] = "1"
            let dylibPath = ("~/.universal-adb-control/helpers/libUniversalControlFrame.dylib" as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: dylibPath) {
                env["DYLD_INSERT_LIBRARIES"] = dylibPath
            }
            p.environment = env
            
            // Mode Windowed Emulator Android:
            // - Bukan fullscreen (layar Mac tetap terlihat)
            // - Ukuran smartphone proporsional (380x820)
            // - Resizable window dengan tombol Close, Minimize, Zoom
            // - Bezel melengkung & punch-hole camera dari overlay dylib
            // - Always-on-top mengambang di atas desktop Mac
            p.arguments = [
                "-s", targetSerial,
                "--window-width=380",
                "--window-height=820",
                "--always-on-top",
                "--stay-awake",
                "--shortcut-mod=rctrl",
                "--no-audio",
                "--video-codec=\(config.videoCodec)",
                "--video-bit-rate=\(config.videoBitrate)",
                "--max-size=\(config.maxSize)",
                "--max-fps=\(config.maxFps)",
                "--video-buffer=\(config.videoBufferMs)",
                "--keyboard=uhid",
                "--mouse=uhid",
                "--window-title=Universal ADB Control"
            ]
            
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            
            do {
                try p.run()
                Logger.shared.log("Launched Universal ADB Control Display with PID: \(p.processIdentifier)")
                
                var attempts = 0
                while attempts < 30 {
                    Thread.sleep(forTimeInterval: 0.2)
                    if let app = self.getDisplayApp() {
                        DispatchQueue.main.async {
                            let script = """
                            tell application "System Events"
                                set frontmost of (first process whose bundle identifier is "com.universal.adb.control.display" or name contains "UniversalADBControlDisplay" or name contains "scrcpy") to true
                            end tell
                            """
                            self.executeAppleScript(script)
                            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
                            self.isControlling = true
                            self.isLaunching = false
                            self.showNotification(title: "Universal ADB Control", message: "Mengontrol Android (Mode Emulator, ⌘⌥T untuk kembali)")
                        }
                        return
                    }
                    if !p.isRunning {
                        break
                    }
                    attempts += 1
                }
                
                DispatchQueue.main.async {
                    self.isLaunching = false
                    if p.isRunning {
                        self.isControlling = true
                        self.showNotification(title: "Universal ADB Control", message: "Layar kontrol aktif (⌘⌥T untuk kembali)")
                    } else {
                        self.isControlling = false
                        self.showNotification(title: "Universal ADB Control", message: "Layar kontrol berhenti tak terduga")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLaunching = false
                    self.isControlling = false
                    self.showNotification(title: "Universal ADB Control", message: "Gagal menjalankan kontrol layar: \(error.localizedDescription)")
                }
            }
        }
    }
}
