import Cocoa
import SwiftUI

@available(macOS 11.0, *)
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow?
    let appState = AppState()
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        
        let contentView = MainView(state: appState)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 980, height: 680)
        window.center()
        window.title = "Universal ADB Control"
        window.contentView = NSHostingView(rootView: contentView)
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        self.window = window
        
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "ipad.and.iphone", accessibilityDescription: "Universal ADB Control")
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Buka Panel Kontrol", action: #selector(showWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Toggle Kontrol (⌘⌥T)", action: #selector(toggleControl), keyEquivalent: "t"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Keluar", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    @objc func showWindow() {
        if let win = window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    @objc func toggleControl() {
        appState.toggleDisplay()
    }
    
    @objc func quitApp() {
        appState.stopDisplay()
        NSApplication.shared.terminate(nil)
    }
    
    func windowWillClose(_ notification: Notification) {
        appState.stopDisplay()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        appState.stopDisplay()
    }
}

@available(macOS 11.0, *)
@main
struct UniversalControlApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
