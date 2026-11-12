import SwiftUI
import AppKit

struct MainView: View {
    @ObservedObject var state: AppState
    @State private var showDevices = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 12) {
            topBar
            GeometryReader { geo in
                PhoneView(state: state, availableSize: geo.size, onConnect: { showDevices = true })
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            dock
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(minWidth: 320, minHeight: 380)
        .overlay(alignment: .bottom) { toast }
        .animation(.smooth(duration: 0.25), value: state.toast)
        .animation(.smooth(duration: 0.25), value: state.isStreaming)
        .animation(.smooth(duration: 0.35), value: state.isLandscape)
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
                    dockButton("rotate.right", help: state.isLandscape ? "Rotasi ke Portret" : "Rotasi ke Lanskap", action: state.toggleRotation)
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
    let availableSize: CGSize
    let onConnect: () -> Void

    var body: some View {
        let isLandscape = state.isLandscape
        let ratio = state.screenAspectRatio > 0.1 ? state.screenAspectRatio : (isLandscape ? (20.0 / 9.0) : (9.0 / 20.0))
        let screen = computeScreenSize(availableSize: availableSize, ratio: ratio)
        let bezel: CGFloat = 8
        let bodyW = screen.width + bezel * 2
        let bodyH = screen.height + bezel * 2
        let minDim = min(bodyW, bodyH)
        let bodyRadius: CGFloat = max(minDim * 0.12, 16)
        let screenRadius: CGFloat = max(bodyRadius - bezel, 10)

        ZStack {
            RoundedRectangle(cornerRadius: bodyRadius, style: .continuous)
                .fill(Color(white: 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: bodyRadius, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [Color(white: 0.42), Color(white: 0.14), Color(white: 0.30)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing),
                                      lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)

            ZStack {
                Color.black
                if state.isStreaming {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    idleScreen(screenSize: screen)
                }
            }
            .frame(width: screen.width, height: screen.height)
            .clipShape(RoundedRectangle(cornerRadius: screenRadius, style: .continuous))
            .background(ScreenAnchor(radius: screenRadius) { rect, r in
                state.updateHostGeometry(rect: rect, radius: r)
            })
        }
        .frame(width: bodyW, height: bodyH)
        .overlay(alignment: .topTrailing) {
            sideButtons(isLandscape: isLandscape, bodyDim: isLandscape ? bodyW : bodyH)
        }
    }

    private func computeScreenSize(availableSize: CGSize, ratio: CGFloat) -> CGSize {
        let bezel: CGFloat = 8
        let horizontalPadding: CGFloat = 20
        let verticalPadding: CGFloat = 10

        let maxW = max(availableSize.width - horizontalPadding * 2 - bezel * 2, 80)
        let maxH = max(availableSize.height - verticalPadding * 2 - bezel * 2, 80)

        var screenW = maxW
        var screenH = screenW / ratio

        if screenH > maxH {
            screenH = maxH
            screenW = screenH * ratio
        }
        return CGSize(width: screenW, height: screenH)
    }

    @ViewBuilder
    private func sideButtons(isLandscape: Bool, bodyDim: CGFloat) -> some View {
        let scale = max(bodyDim / 600.0, 0.6)
        if !isLandscape {
            VStack(spacing: 8 * scale) {
                sideKey(width: 4, height: 38 * scale, help: "Volume naik", action: state.sendVolumeUp)
                sideKey(width: 4, height: 38 * scale, help: "Volume turun", action: state.sendVolumeDown)
                sideKey(width: 4, height: 52 * scale, help: "Power", action: state.sendPower)
                    .padding(.top, 14 * scale)
            }
            .padding(.top, 90 * scale)
            .offset(x: 6)
        } else {
            HStack(spacing: 8 * scale) {
                sideKey(width: 38 * scale, height: 4, help: "Volume naik", action: state.sendVolumeUp)
                sideKey(width: 38 * scale, height: 4, help: "Volume turun", action: state.sendVolumeDown)
                sideKey(width: 52 * scale, height: 4, help: "Power", action: state.sendPower)
                    .padding(.leading, 14 * scale)
            }
            .padding(.trailing, 90 * scale)
            .offset(y: -6)
        }
    }

    private func sideKey(width: CGFloat, height: CGFloat, help: String, action: @escaping () -> Void) -> some View {
        SideKey(width: width, height: height, action: action).help(help)
    }

    @ViewBuilder private func idleScreen(screenSize: CGSize) -> some View {
        LinearGradient(colors: [Color(white: 0.10), Color(white: 0.02)], startPoint: .top, endPoint: .bottom)
        if state.activeDevice != nil {
            let btnDim = min(screenSize.width, screenSize.height) * 0.22
            let iconSize = min(screenSize.width, screenSize.height) * 0.08
            VStack(spacing: 12) {
                Button(action: state.startDisplay) {
                    Image(systemName: "play.fill")
                        .font(.system(size: max(iconSize, 18), weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: max(btnDim, 48), height: max(btnDim, 48))
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
                    .frame(width: 56, height: 56)
                    .contentShape(Circle())
            }
            .buttonStyle(.interactiveGlass)
            .liquidGlass(in: Circle(), interactive: true)
            .help("Hubungkan perangkat")
        }
    }
}

private struct SideKey: View {
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Capsule()
                .fill(Color(white: hover ? 0.42 : 0.24))
                .frame(width: width, height: height)
                .frame(width: max(width, 14), height: max(height, 14))
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
