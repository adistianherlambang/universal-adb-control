#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

mkdir -p bin

echo "==> Mengompilasi Device Frame Overlay dylib..."
clang -dynamiclib -O2 -framework Cocoa src/frame/DeviceFrameOverlay.m -o bin/libUniversalControlFrame.dylib

echo "==> Mengompilasi universal-adb-control-daemon..."
swiftc -O \
    src/daemon/AdbTransport.swift \
    src/daemon/ClipboardDaemon.swift \
    src/daemon/ControlManager.swift \
    src/daemon/Models.swift \
    src/daemon/PasteboardManager.swift \
    src/daemon/main.swift \
    -o bin/universal-adb-control-daemon

echo "==> Mengompilasi Universal ADB Control GUI..."
swiftc -O -parse-as-library \
    src/gui/AppState.swift \
    src/gui/MainView.swift \
    src/gui/main.swift \
    -o bin/UniversalADBControlGUI

echo "==> Sukses! Binary tersedia di folder bin/"

