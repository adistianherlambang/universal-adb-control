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
    
    private func getScrcpyApp() -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        for app in apps {
            if app.bundleIdentifier == "org.freedesktop.scrcpy" || (app.localizedName?.lowercased().contains("scrcpy") ?? false) {
                return app
            }
        }
        return nil
    }
    
    public func showNotification(title: String, message: String) {
        let appleScript = "display notification \"\(message)\" with title \"\(title)\""
        executeAppleScript(appleScript)
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
        
        let scrcpyApp = getScrcpyApp()
        let isRunning = (scrcpyApp != nil && !(scrcpyApp?.isTerminated ?? true))
        
        if isControlling && isRunning {
            // Mode kontrol sedang aktif -> Kembali ke Mac
            switchToMac()
        } else if isRunning {
            // Scrcpy sudah ada tapi sedang disembunyikan -> Buka kembali ke Android
            switchToAndroid()
        } else {
            // Scrcpy belum berjalan -> Luncurkan baru
            launchScrcpy()
        }
    }
    
    private func switchToMac() {
        isControlling = false
        
        if let app = getScrcpyApp() {
            app.hide()
            let script = "tell application \"System Events\" to set visible of first process whose name contains \"scrcpy\" to false"
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
        guard let app = getScrcpyApp(), !app.isTerminated else {
            launchScrcpy()
            return
        }
        
        lastFrontmostApp = NSWorkspace.shared.frontmostApplication
        savedMousePos = CGEvent(source: nil)?.location
        
        let script = """
        tell application "System Events"
            set visible of first process whose name contains "scrcpy" to true
            set frontmost of first process whose name contains "scrcpy" to true
        end tell
        """
        executeAppleScript(script)
        app.unhide()
        app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        
        isControlling = true
        showNotification(title: "Universal ADB Control", message: "Mengontrol Android (Layar penuh, ⌘⌥T untuk kembali)")
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
    
    private func launchScrcpy() {
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
        
        lastFrontmostApp = NSWorkspace.shared.frontmostApplication
        savedMousePos = CGEvent(source: nil)?.location
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let p = Process()
            p.executableURL = URL(fileURLWithPath: self.scrcpyBin)
            
            // Fullscreen capture: seluruh layar tertutup scrcpy sehingga kursor mouse
            // dan keyboard 100% masuk ke Android tanpa ada klik/ketikan yang bocor ke Mac.
            // shortcut-mod diubah ke rctrl agar tombol Cmd dan Option tidak melepas capture scrcpy.
            p.arguments = [
                "-s", targetSerial,
                "--fullscreen",
                "--stay-awake",
                "--shortcut-mod=rctrl",
                "--no-audio",
                "--keyboard=uhid",
                "--mouse=uhid",
                "--window-title=UniversalADBControl"
            ]
            
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            
            do {
                try p.run()
                Logger.shared.log("Launched scrcpy with PID: \(p.processIdentifier)")
                
                var attempts = 0
                while attempts < 30 {
                    Thread.sleep(forTimeInterval: 0.2)
                    if let app = self.getScrcpyApp() {
                        DispatchQueue.main.async {
                            let script = """
                            tell application "System Events"
                                set frontmost of first process whose name contains "scrcpy" to true
                            end tell
                            """
                            self.executeAppleScript(script)
                            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
                            self.isControlling = true
                            self.isLaunching = false
                            self.showNotification(title: "Universal ADB Control", message: "Mengontrol Android (Layar penuh, ⌘⌥T untuk kembali)")
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
                        self.showNotification(title: "Universal ADB Control", message: "scrcpy aktif (Layar penuh, ⌘⌥T untuk kembali)")
                    } else {
                        self.isControlling = false
                        self.showNotification(title: "Universal ADB Control", message: "scrcpy berhenti tak terduga")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLaunching = false
                    self.isControlling = false
                    self.showNotification(title: "Universal ADB Control", message: "Gagal menjalankan scrcpy: \(error.localizedDescription)")
                }
            }
        }
    }
}
