import Foundation
import Cocoa
import Carbon

public final class ControlManager {
    public static let shared = ControlManager()
    
    private var hotKeyRef: EventHotKeyRef?
    private var isLaunching = false
    private var savedMousePos: CGPoint?
    
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
        
        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            ControlManager.shared.handleHotKey()
            return noErr
        }, 1, &eventType, nil, nil)
        
        // kVK_ANSI_T = 0x11 (17)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(cmdKey | optionKey), gMyHotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status == noErr {
            Logger.shared.log("HotKey Cmd+Option+T registered successfully.")
        } else {
            Logger.shared.log("Failed to register HotKey Cmd+Option+T (status \(status))")
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
        if let script = NSAppleScript(source: appleScript) {
            var errorInfo: NSDictionary?
            script.executeAndReturnError(&errorInfo)
        }
    }
    
    public func toggleControl() {
        if isLaunching {
            showNotification(title: "Universal ADB Control", message: "Sedang menghubungkan ke perangkat...")
            return
        }
        
        if let app = getScrcpyApp() {
            if app.isActive {
                // Switch back to Mac
                app.hide()
                if let pos = savedMousePos {
                    CGDisplayMoveCursorToPoint(CGMainDisplayID(), pos)
                }
                showNotification(title: "Universal ADB Control", message: "Kembali ke Mac")
            } else {
                // Switch to Android
                savedMousePos = CGEvent(source: nil)?.location
                app.activate(options: [.activateIgnoringOtherApps])
                showNotification(title: "Universal ADB Control", message: "Mengontrol Android (Mouse & Keyboard)")
            }
            return
        }
        
        // Not running -> Launch scrcpy
        launchScrcpy()
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
        
        // Load config to check if specific device preferred
        let config = DaemonConfig.load()
        var targetSerial: String = validDevs[0].serial
        if let pref = config.preferredDevice, !pref.isEmpty {
            if validDevs.contains(where: { $0.serial == pref }) {
                targetSerial = pref
            }
        }
        
        isLaunching = true
        showNotification(title: "Universal ADB Control", message: "Menghubungkan (\(targetSerial))...")
        savedMousePos = CGEvent(source: nil)?.location
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Check if device is Wi-Fi or USB
            let isWifi = targetSerial.contains(":") || targetSerial.contains("._tcp")
            
            let p = Process()
            p.executableURL = URL(fileURLWithPath: self.scrcpyBin)
            
            // Parameters for seamless control:
            // UHID keyboard & mouse + no audio + small window positioned offscreen once captured
            if isWifi {
                p.arguments = [
                    "-s", targetSerial,
                    "--keyboard=uhid",
                    "--mouse=uhid",
                    "--no-audio",
                    "--window-title=UniversalADBControl",
                    "--window-borderless",
                    "--window-width=300",
                    "--window-height=600",
                    "--window-x=100",
                    "--window-y=100"
                ]
            } else {
                p.arguments = [
                    "--otg",
                    "-s", targetSerial,
                    "--window-title=UniversalADBControl"
                ]
            }
            
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            
            do {
                try p.run()
                Logger.shared.log("Launched scrcpy with PID: \(p.processIdentifier)")
                
                // Poll for window/app readiness
                var attempts = 0
                while attempts < 25 {
                    Thread.sleep(forTimeInterval: 0.2)
                    if let app = self.getScrcpyApp() {
                        DispatchQueue.main.async {
                            app.activate(options: [.activateIgnoringOtherApps])
                            self.showNotification(title: "Universal ADB Control", message: "Mengontrol Android (Mouse & Keyboard)")
                            self.isLaunching = false
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
                        self.showNotification(title: "Universal ADB Control", message: "scrcpy aktif tetapi jendela belum siap")
                    } else {
                        self.showNotification(title: "Universal ADB Control", message: "scrcpy berhenti tak terduga")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLaunching = false
                    self.showNotification(title: "Universal ADB Control", message: "Gagal menjalankan scrcpy: \(error.localizedDescription)")
                }
            }
        }
    }
}

