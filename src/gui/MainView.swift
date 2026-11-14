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
                    } else if let logo = loadBrandLogo() {
                        Image(nsImage: logo)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                    }
                    Text(state.activeDevice?.displayName ?? "Tidak ada perangkat")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
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
        .overlay(alignment: .leading) {
            if state.isStreaming {
                metricsBadge
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
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

    private var metricsBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(state.currentFps >= 50 ? Color.green : (state.currentFps > 0 ? Color.yellow : Color.secondary.opacity(0.5)))
                .frame(width: 6, height: 6)

            Text("\(state.currentFps) FPS")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(state.currentFps > 0 ? .primary : .secondary)

            Text("•")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.tertiary)

            Text("\(state.currentLatencyMs) ms")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(state.currentLatencyMs < 45 ? .secondary : (state.currentLatencyMs < 90 ? Color.orange : Color.red))
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .liquidGlass(in: Capsule())
        .help("FPS render: \(state.currentFps) (0 saat layar diam)\nLatensi jaringan RTT: \(state.currentLatencyMs) ms")
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
            VStack(spacing: 16) {
                if let logo = loadBrandLogo() {
                    Image(nsImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                }

                VStack(spacing: 4) {
                    Text("Universal ADB Control")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Hubungkan perangkat untuk memulai")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Button(action: onConnect) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Tambah Perangkat")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 32)
                    .contentShape(Capsule())
                }
                .buttonStyle(.interactiveGlass)
                .liquidGlass(in: Capsule(), interactive: true, tint: .accentColor)
                .help("Hubungkan perangkat Android")
            }
        }
    }
}

private func loadBrandLogo() -> NSImage? {
    if let img = NSImage(named: "adbLogo") { return img }
    if let path = Bundle.main.path(forResource: "adbLogo", ofType: "jpg"), let img = NSImage(contentsOfFile: path) {
        return img
    }
    if let path = Bundle.main.path(forResource: "adbLogo", ofType: "png"), let img = NSImage(contentsOfFile: path) {
        return img
    }
    let localJpg = ("adbLogo.jpg" as NSString).expandingTildeInPath
    if let img = NSImage(contentsOfFile: localJpg) { return img }
    let assetJpg = ("assets/adbLogo.jpg" as NSString).expandingTildeInPath
    if let img = NSImage(contentsOfFile: assetJpg) { return img }
    let assetPng = ("assets/adbLogo.png" as NSString).expandingTildeInPath
    if let img = NSImage(contentsOfFile: assetPng) { return img }
    return nil
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
    case qr = "QR Code"
    case direct = "IP"
    case pair = "Kode"

    var id: String { rawValue }
}

private struct DevicePopover: View {
    @ObservedObject var state: AppState
    @Binding var isPresented: Bool

    @State private var mode: ConnectionMode = .qr
    @State private var directAddress = ""
    @State private var pairAddress = ""
    @State private var pairCode = ""
    @State private var isAddingDevice = false
    @State private var qrImage: NSImage?
    @State private var currentCode = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.devices.isEmpty {
                // Saat belum ada perangkat terhubung: langsung tampilkan input koneksi
                connectionSection
            } else {
                // Saat sudah ada perangkat: tampilkan daftar perangkat
                ForEach(state.devices) { dev in
                    deviceRow(dev)
                }

                if !isAddingDevice {
                    Button {
                        withAnimation(.smooth(duration: 0.2)) {
                            isAddingDevice = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("Tambah Perangkat Lain")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.interactiveGlass)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 7, style: .continuous), interactive: true)
                    .padding(.top, 2)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Tambah Perangkat")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                withAnimation(.smooth(duration: 0.2)) {
                                    isAddingDevice = false
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, height: 18)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 4)

                        connectionSection
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(12)
        .frame(width: 270)
        .onAppear {
            if mode == .qr && (isAddingDevice || state.devices.isEmpty) {
                regenerateQR()
            }
        }
        .onDisappear {
            state.stopQRPairing()
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .qr && (isAddingDevice || state.devices.isEmpty) {
                regenerateQR()
            } else {
                state.stopQRPairing()
            }
        }
        .onChange(of: isAddingDevice) { _, adding in
            if adding && mode == .qr {
                regenerateQR()
            } else if !adding {
                state.stopQRPairing()
            }
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $mode) {
                ForEach(ConnectionMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if mode == .qr {
                qrSection
            } else if mode == .direct {
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
    }

    private var qrSection: some View {
        VStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)

                if let img = qrImage {
                    Image(nsImage: img)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } else {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .frame(width: 148, height: 148)

            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    if state.isQrPairing {
                        ProgressView()
                            .scaleEffect(0.55)
                            .frame(width: 12, height: 12)
                    } else {
                        Circle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 6, height: 6)
                    }

                    Text(state.qrPairingStatus)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Button(action: regenerateQR) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Buat kode baru")
                }

                Text("Opsi Pengembang > Debug Nirkabel > Pindai QR")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func regenerateQR() {
        let randHex = String(format: "%04x%04x", arc4random() % 65536, arc4random() % 65536)
        let sName = "uac-\(randHex)"
        let code = String(format: "%06d", arc4random() % 900000 + 100000)
        currentCode = code
        let payload = "WIFI:T:ADB;S:\(sName);P:\(code);;"
        qrImage = QRCodeHelper.generate(from: payload, size: 280)
        state.startQRPairing(serviceName: sName, code: code) { success in
            if success {
                withAnimation(.smooth(duration: 0.25)) {
                    isAddingDevice = false
                }
            }
        }
    }

    private func deviceRow(_ dev: AdbDeviceItem) -> some View {
        let isSelected = dev.serial == state.activeDevice?.serial
        return HStack(spacing: 8) {
            Button {
                guard dev.isReady else { return }
                state.selectDevice(dev.serial)
                isPresented = false
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill((dev.isWifi ? Color.blue : Color.green).opacity(0.14))
                            .frame(width: 24, height: 24)
                        Image(systemName: dev.isWifi ? "wifi" : "cable.connector")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(dev.isWifi ? Color.blue : Color.green)
                    }

                    Text(dev.displayName)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(dev.isReady ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSelected {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.20))
                        .overlay(Circle().stroke(Color.accentColor.opacity(0.40), lineWidth: 0.8))
                        .frame(width: 18, height: 18)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }

            DeviceDisconnectButton {
                state.disconnect(dev.serial)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                    )
            }
        }
    }

    private func submitPair() {
        state.stopQRPairing()
        state.pairAndConnect(pairingAddress: pairAddress, code: pairCode)
        pairCode = ""
        isAddingDevice = false
    }

    private func submitDirect() {
        state.stopQRPairing()
        state.connectWifi(directAddress)
        directAddress = ""
        isAddingDevice = false
    }
}

private struct DeviceDisconnectButton: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(hover ? Color.red.opacity(0.25) : Color.white.opacity(0.06))
                    .overlay(Circle().stroke(hover ? Color.red.opacity(0.50) : Color.white.opacity(0.14), lineWidth: 0.8))
                    .frame(width: 20, height: 20)
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(hover ? Color.red : Color.secondary)
            }
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.smooth(duration: 0.15)) { hover = h } }
        .help("Putuskan koneksi")
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

            if state.isStreaming {
                Divider()
                HStack {
                    Text("Performa")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(state.currentFps) FPS • \(state.currentLatencyMs) ms")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
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
        for name in [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didMoveNotification] {
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
