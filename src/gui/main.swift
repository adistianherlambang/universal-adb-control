import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow?
    let appState = AppState()
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 380, height: 700)
        window.title = "Universal ADB Control"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear

        // Latar kaca buram mengikuti desktop di belakang jendela
        let background = NSVisualEffectView()
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .followsWindowActiveState

        let host = NSHostingView(rootView: MainView(state: appState))
        host.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            host.topAnchor.constraint(equalTo: background.topAnchor),
            host.bottomAnchor.constraint(equalTo: background.bottomAnchor)
        ])
        window.contentView = background
        window.center()
        window.setFrameAutosaveName("UniversalADBControlMain")
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        self.window = window

        // Pintasan ⌘⌥T dari daemon meminta GUI menyalakan layar terintegrasi
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.universal.adb.control.start"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.showWindow()
            self?.appState.startDisplay()
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "Universal ADB Control")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Buka", action: #selector(showWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Mulai / Berhenti", action: #selector(toggleControl), keyEquivalent: "t"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Keluar", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc func showWindow() {
        guard let win = window else { return }
        if win.isMiniaturized { win.deminiaturize(nil) }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stopDisplay()
    }
}

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
