import Cocoa
import SwiftUI
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow?
    let appState = AppState()
    var statusItem: NSStatusItem?
    var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupMenuBar()
        setupEventMonitors()
        setupGlobalHotKey()

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

        // Pintasan ⌘⌥T atau sinyal bangun dari daemon
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.universal.adb.control.start"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.showWindow()
            self?.appState.startDisplay()
        }

        // Permintaan sembunyikan ke background dari helper scrcpy
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.universal.adb.control.hide"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.hideToBackground()
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupGlobalHotKey() {
        var gMyHotKeyID = EventHotKeyID()
        gMyHotKeyID.signature = OSType(0x55414347) // "UACG"
        gMyHotKeyID.id = UInt32(200)

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)

        InstallEventHandler(GetEventDispatcherTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name("com.universal.adb.control.toggleHotKey"), object: nil)
            }
            return noErr
        }, 1, &eventType, nil, nil)

        // kVK_ANSI_T = 0x11 (17) -> Cmd + Option + T
        RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(cmdKey | optionKey), gMyHotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)

        NotificationCenter.default.addObserver(forName: Notification.Name("com.universal.adb.control.toggleHotKey"), object: nil, queue: .main) { [weak self] _ in
            self?.handleGlobalHotKey()
        }
    }

    @objc func handleGlobalHotKey() {
        guard let win = window else { return }
        if win.isVisible && NSApp.isActive && appState.isStreaming {
            hideToBackground()
        } else {
            showWindow()
            if !appState.isStreaming {
                appState.startDisplay()
            }
        }
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
        let hideToBgItem = NSMenuItem(title: "Sembunyikan ke Background", action: #selector(hideToBackground), keyEquivalent: "q")
        let quitItem = NSMenuItem(title: "Keluar Sepenuhnya", action: #selector(quitAppCompletely), keyEquivalent: "Q")
        quitItem.keyEquivalentModifierMask = [.command, .shift]
        appMenu.addItem(hideToBgItem)
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
        let closeItem = NSMenuItem(title: "Tutup ke Background", action: #selector(hideToBackground), keyEquivalent: "w")
        let miniItem = NSMenuItem(title: "Kecilkan", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(closeItem)
        windowMenu.addItem(miniItem)
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func setupEventMonitors() {
        // Intersepsi lokal memastikan ⌘Q dan ⌘W selalu menyembunyikan jendela ke background
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) {
                let key = event.charactersIgnoringModifiers?.lowercased()
                if key == "q" || key == "w" {
                    self?.hideToBackground()
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
        menu.addItem(NSMenuItem(title: "Buka Jendela", action: #selector(showWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Mulai / Berhenti Layar (⌘⌥T)", action: #selector(toggleControl), keyEquivalent: "t"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Sembunyikan ke Background", action: #selector(hideToBackground), keyEquivalent: "w"))
        menu.addItem(NSMenuItem(title: "Keluar Sepenuhnya", action: #selector(quitAppCompletely), keyEquivalent: "q"))
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

    @objc func hideToBackground() {
        appState.stopDisplay()
        window?.orderOut(nil)
    }

    @objc func quitAppCompletely() {
        appState.stopDisplay()
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/pkill"), arguments: ["-f", "UniversalADBControlDisplay"])
        NSApplication.shared.terminate(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            exit(0)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideToBackground()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        appState.stopDisplay()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
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
