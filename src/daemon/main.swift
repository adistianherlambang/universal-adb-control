import Foundation
import Cocoa

let config = DaemonConfig.load()

// Locate agent DEX file: check ~/.universal-adb-control/classes.dex or ~/.universal-clipboard/classes.dex
var dexPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
if dexPath.isEmpty {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let uacDex = home.appendingPathComponent(".universal-adb-control/classes.dex").path
    let ucDex = home.appendingPathComponent(".universal-clipboard/classes.dex").path
    if FileManager.default.fileExists(atPath: uacDex) {
        dexPath = uacDex
    } else if FileManager.default.fileExists(atPath: ucDex) {
        dexPath = ucDex
    }
}

guard FileManager.default.fileExists(atPath: dexPath) else {
    print("Error: Android agent classes.dex not found at: \(dexPath)")
    exit(1)
}

// Initialize NSApplication for event loop and Cocoa hotkeys
let app = NSApplication.shared
app.setActivationPolicy(.accessory) // Runs cleanly as background accessory without dock icon clutter

// 1. Register global hotkey Cmd+Option+T for Mouse & Keyboard control FIRST
ControlManager.shared.registerHotKey()

// 2. Start continuous clipboard sync daemon in background
let daemon = ClipboardDaemon(config: config, dexPath: dexPath)
daemon.start()

Logger.shared.log("Universal ADB Control Daemon started (Clipboard: Active, HotKey: Cmd+Opt+T)")

// 3. Run main event loop to listen for hotkey and dispatch events
app.run()

