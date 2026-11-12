import SwiftUI
import AppKit

// Ukuran dasar ponsel (skala 1.0). Rasio layar 9:20 mengikuti HP modern.
private enum Phone {
    static let screen = CGSize(width: 288, height: 640)
    static let bezel: CGFloat = 9
    static let body = CGSize(width: screen.width + bezel * 2, height: screen.height + bezel * 2)
    static let bodyRadius: CGFloat = 46
    static let screenRadius: CGFloat = 38
}

struct MainView: View {
    @ObservedObject var state: AppState
    @State private var showDevices = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 16) {
            topBar
            GeometryReader { geo in
                let scale = min((geo.size.height) / Phone.body.height,
                                (geo.size.width - 48) / Phone.body.width, 1.6)
                PhoneView(state: state, scale: max(scale, 0.5), onConnect: { showDevices = true })
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            dock
        }
        .padding(.top, 8)
        .padding(.bottom, 22)
        .frame(minWidth: 380, minHeight: 700)
        .overlay(alignment: .bottom) { toast }
        .animation(.smooth(duration: 0.25), value: state.toast)
        .animation(.smooth(duration: 0.25), value: state.isStreaming)
        .onChange(of: showDevices || showSettings) { _, open in state.overlayOpen = open }
    }

    // MARK: Bar atas — nama perangkat (klik untuk ganti) + pengaturan

    private var topBar: some View {
        HStack {
            Spacer()
            Button { showDevices.toggle() } label: {
                HStack(spacing: 6) {
                    if let dev = state.activeDevice {
                        Image(systemName: dev.isWifi ? "wifi" : "cable.connector")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(state.activeDevice?.displayName ?? "Tidak ada perangkat")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 32)
                .contentShape(Capsule())
            }
            .buttonStyle(.interactiveGlass)
            .liquidGlass(in: Capsule(), interactive: true)
            .popover(isPresented: $showDevices, arrowEdge: .bottom) {
                DevicePopover(state: state, isPresented: $showDevices)
            }
            Spacer()
        }
        .overlay(alignment: .trailing) {
            Button { showSettings.toggle() } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.interactiveGlass)
            .liquidGlass(in: Circle(), interactive: true)
            .help("Pengaturan")
            .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                SettingsPopover(state: state)
            }
            .padding(.trailing, 16)
        }
        .frame(height: 32)
    }

    // MARK: Dock bawah — navigasi Android + mulai/berhenti

    private var dock: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    dockButton("chevron.backward", help: "Kembali", action: state.sendBack)
                    dockButton("circle", help: "Beranda", action: state.sendHome)
                    dockButton("square", help: "Aplikasi terkini", action: state.sendRecents)
                }
                .padding(4)
                .liquidGlass(in: Capsule())

                Button(action: state.toggleDisplay) {
                    Image(systemName: state.isStreaming ? "stop.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.interactiveGlass)
                .liquidGlass(in: Circle(), interactive: true, tint: state.isStreaming ? nil : .accentColor)
                .disabled(state.activeDevice == nil)
                .help(state.isStreaming ? "Berhenti" : "Mulai  ⌘⌥T")
            }
        }
        .disabled(state.activeDevice == nil)
        .opacity(state.activeDevice == nil ? 0.5 : 1)
    }

    private func dockButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        DockIconButton(symbol: symbol, help: help, action: action)
    }

    @ViewBuilder private var toast: some View {
        if let message = state.toast {
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .liquidGlass(in: Capsule())
                .padding(.bottom, 84)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }
}

private struct DockIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 40, height: 40)
                .background {
                    if isHovered {
                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.8))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.interactiveGlass)
        .onHover { hover in
            withAnimation(.smooth(duration: 0.18)) {
                isHovered = hover
            }
        }
        .help(help)
    }
}

// MARK: - Ponsel

private struct PhoneView: View {
    @ObservedObject var state: AppState
    let scale: CGFloat
    let onConnect: () -> Void

    var body: some View {
        let screen = CGSize(width: Phone.screen.width * scale, height: Phone.screen.height * scale)
        let radius = Phone.screenRadius * scale

        ZStack {
            RoundedRectangle(cornerRadius: Phone.bodyRadius * scale, style: .continuous)
                .fill(Color(white: 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: Phone.bodyRadius * scale, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [Color(white: 0.42), Color(white: 0.14), Color(white: 0.30)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing),
                                      lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.35), radius: 24 * scale, y: 12 * scale)

            ZStack {
                Color.black
                if state.isStreaming {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    idleScreen
                }
                // Lubang kamera (saat streaming, kamera digambar ulang di atas layar oleh helper)
                VStack {
                    Circle().fill(Color(white: 0.02))
                        .overlay(Circle().stroke(Color(white: 0.18), lineWidth: 1))
                        .frame(width: 10 * scale, height: 10 * scale)
                        .padding(.top, 12 * scale)
                    Spacer()
                }
            }
            .frame(width: screen.width, height: screen.height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(ScreenAnchor(radius: radius) { rect, r in state.updateHostGeometry(rect: rect, radius: r) })
        }
        .frame(width: Phone.body.width * scale, height: Phone.body.height * scale)
        .overlay(alignment: .topTrailing) { sideButtons }
    }

    // Tombol samping fisik: volume naik, volume turun, power
    private var sideButtons: some View {
        VStack(spacing: 10 * scale) {
            sideKey(height: 44, help: "Volume naik", action: state.sendVolumeUp)
            sideKey(height: 44, help: "Volume turun", action: state.sendVolumeDown)
            sideKey(height: 62, help: "Power", action: state.sendPower)
                .padding(.top, 18 * scale)
        }
        .padding(.top, 120 * scale)
        .offset(x: 6)
    }

    private func sideKey(height: CGFloat, help: String, action: @escaping () -> Void) -> some View {
        SideKey(height: height * scale, action: action).help(help)
    }

    @ViewBuilder private var idleScreen: some View {
        LinearGradient(colors: [Color(white: 0.10), Color(white: 0.02)], startPoint: .top, endPoint: .bottom)
        if state.activeDevice != nil {
            VStack(spacing: 14) {
                Button(action: state.startDisplay) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .contentShape(Circle())
                }
                .buttonStyle(.interactiveGlass)
                .liquidGlass(in: Circle(), interactive: true)
                Text("⌘⌥T")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
            }
        } else {
            Button(action: onConnect) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .contentShape(Circle())
            }
            .buttonStyle(.interactiveGlass)
            .liquidGlass(in: Circle(), interactive: true)
            .help("Hubungkan perangkat")
        }
    }
}

private struct SideKey: View {
    let height: CGFloat
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Capsule()
                .fill(Color(white: hover ? 0.42 : 0.24))
                .frame(width: 4, height: height)
                .frame(width: 14, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Popover perangkat

private enum ConnectionMode: String, CaseIterable, Identifiable {
    case direct = "IP"
    case pair = "Kode"

    var id: String { rawValue }
}

private struct DevicePopover: View {
    @ObservedObject var state: AppState
    @Binding var isPresented: Bool

    @State private var mode: ConnectionMode = .direct
    @State private var directAddress = ""
    @State private var pairAddress = ""
    @State private var pairCode = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.devices.isEmpty {
                Text("Tidak ada perangkat")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            } else {
                ForEach(state.devices) { dev in
                    deviceRow(dev)
                }
            }

            Divider().opacity(0.3)

            Picker("", selection: $mode) {
                ForEach(ConnectionMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if mode == .direct {
                HStack(spacing: 8) {
                    TextField("Alamat IP", text: $directAddress)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .liquidGlass(in: Capsule())
                        .onSubmit(submitDirect)

                    Button(action: submitDirect) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 30, height: 30)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.interactiveGlass)
                    .liquidGlass(in: Circle(), interactive: true, tint: .accentColor)
                    .disabled(directAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                HStack(spacing: 6) {
                    TextField("IP:Port", text: $pairAddress)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .liquidGlass(in: Capsule())

                    TextField("Kode", text: $pairCode)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .frame(width: 64)
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                        .liquidGlass(in: Capsule())
                        .onSubmit(submitPair)

                    Button(action: submitPair) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 30, height: 30)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.interactiveGlass)
                    .liquidGlass(in: Circle(), interactive: true, tint: .accentColor)
                    .disabled(pairAddress.trimmingCharacters(in: .whitespaces).isEmpty || pairCode.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(12)
        .frame(width: 250)
    }

    private func deviceRow(_ dev: AdbDeviceItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: dev.isWifi ? "wifi" : "cable.connector")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(dev.displayName)
                .font(.system(size: 12))
                .foregroundStyle(dev.isReady ? .primary : .secondary)
            Spacer(minLength: 8)
            if dev.serial == state.activeDevice?.serial {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary)
            }
            if dev.isWifi {
                Button {
                    state.disconnect(dev.serial)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Putuskan")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .contentShape(Rectangle())
        .onTapGesture {
            guard dev.isReady else { return }
            state.selectDevice(dev.serial)
            isPresented = false
        }
    }

    private func submitPair() {
        state.pairAndConnect(pairingAddress: pairAddress, code: pairCode)
        pairCode = ""
    }

    private func submitDirect() {
        state.connectWifi(directAddress)
        directAddress = ""
    }
}

// MARK: - Popover pengaturan

private struct SettingsPopover: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Kualitas").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Picker("", selection: Binding(get: { state.quality }, set: { state.setQuality($0) })) {
                    ForEach(StreamQuality.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Toggle("Sinkron clipboard", isOn: Binding(get: { state.isSyncOn }, set: { state.setSync($0) }))
                .toggleStyle(.switch)
                .font(.system(size: 13))
        }
        .padding(16)
        .frame(width: 260)
    }
}

// MARK: - Penanda posisi layar (dipakai helper untuk menempel tepat di area layar)

private struct ScreenAnchor: NSViewRepresentable {
    let radius: CGFloat
    let onChange: (NSRect, CGFloat) -> Void

    func makeNSView(context: Context) -> AnchorView {
        let v = AnchorView()
        v.onChange = onChange
        v.radius = radius
        return v
    }

    func updateNSView(_ v: AnchorView, context: Context) {
        v.onChange = onChange
        v.radius = radius
        v.report()
    }
}

final class AnchorView: NSView {
    var onChange: ((NSRect, CGFloat) -> Void)?
    var radius: CGFloat = 38
    private var observers: [NSObjectProtocol] = []

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        report()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        guard let window else { return }
        for name in [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.report()
            })
        }
        report()
    }

    func report() {
        guard window != nil else { return }
        onChange?(convert(bounds, to: nil), radius)
    }
}
