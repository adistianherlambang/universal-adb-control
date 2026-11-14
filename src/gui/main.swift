import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow?
    let appState = AppState()
    var statusItem: NSStatusItem?

    private var dragTimer: Timer?
    private var startWindowFrame: NSRect = .zero
    private var startMouseLocation: NSPoint = .zero
    private var isDraggingWindow: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupMenuBar()
        setupEventMonitors()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 320, height: 360)
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
        appState.updateWindowFrame(window.frame, windowNumber: UInt32(window.windowNumber))

        // Otomatis nyalakan layar saat GUI dibuka
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.appState.startDisplay()
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // 1. Menu Aplikasi
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Tentang Universal ADB Control", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        let hideItem = NSMenuItem(title: "Sembunyikan Universal ADB Control", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(title: "Sembunyikan Lainnya", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        let showAllItem = NSMenuItem(title: "Tampilkan Semua", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(hideItem)
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(showAllItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Keluar Universal ADB Control", action: #selector(quitApp), keyEquivalent: "q")
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 2. Menu Edit (Aksi teks & clipboard standar)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Urungkan", action: Selector(("undo:")), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "Ulangi", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Potong", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Salin", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Tempel", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Pilih Semua", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // 3. Menu Jendela
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Jendela")
        let closeItem = NSMenuItem(title: "Tutup Jendela", action: #selector(quitApp), keyEquivalent: "w")
        let miniItem = NSMenuItem(title: "Kecilkan", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(closeItem)
        windowMenu.addItem(miniItem)
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func setupEventMonitors() {
        // Intersepsi lokal memastikan ⌘Q dan ⌘W selalu keluar total dari GUI
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) {
                let key = event.charactersIgnoringModifiers?.lowercased()
                if key == "q" || key == "w" {
                    self?.quitApp()
                    return nil
                }
            }
            return event
        }
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
        appState.setWindowHidden(false)
        appState.updateWindowFrame(win.frame, windowNumber: UInt32(win.windowNumber))
    }

    @objc func toggleControl() {
        appState.toggleDisplay()
    }

    @objc func quitApp() {
        appState.stopDisplay()
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/pkill"), arguments: ["-f", "UniversalADBControlDisplay"])
        NSApplication.shared.terminate(nil)
        exit(0)
    }

    // MARK: - NSWindowDelegate (Sinkronisasi posisi & live dragging)

    func windowWillMove(_ notification: Notification) {
        guard let win = self.window else { return }
        startWindowFrame = win.frame
        startMouseLocation = NSEvent.mouseLocation
        isDraggingWindow = true

        dragTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.handleLiveDrag()
        }
        dragTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func windowDidMove(_ notification: Notification) {
        stopDragTracking()
        if let win = self.window {
            appState.updateWindowFrame(win.frame, windowNumber: UInt32(win.windowNumber))
        }
    }

    func windowDidResize(_ notification: Notification) {
        if let win = self.window {
            appState.updateWindowFrame(win.frame, windowNumber: UInt32(win.windowNumber))
        }
    }

    func windowDidMiniaturize(_ notification: Notification) {
        appState.setWindowHidden(true)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        appState.setWindowHidden(false)
        if let win = self.window {
            appState.updateWindowFrame(win.frame, windowNumber: UInt32(win.windowNumber))
        }
    }

    private func handleLiveDrag() {
        guard let win = self.window, isDraggingWindow else { return }
        if (NSEvent.pressedMouseButtons & 1) == 0 {
            stopDragTracking()
            appState.updateWindowFrame(win.frame, windowNumber: UInt32(win.windowNumber))
            return
        }
        let currentMouse = NSEvent.mouseLocation
        let deltaX = currentMouse.x - startMouseLocation.x
        let deltaY = currentMouse.y - startMouseLocation.y
        let liveFrame = NSRect(
            x: startWindowFrame.origin.x + deltaX,
            y: startWindowFrame.origin.y + deltaY,
            width: startWindowFrame.width,
            height: startWindowFrame.height
        )
        appState.updateWindowFrame(liveFrame, windowNumber: UInt32(win.windowNumber))
    }

    private func stopDragTracking() {
        isDraggingWindow = false
        dragTimer?.invalidate()
        dragTimer = nil
    }

    func windowWillClose(_ notification: Notification) {
        quitApp()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
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
        signal(SIGTERM) { _ in exit(0) }
        signal(SIGINT) { _ in exit(0) }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
