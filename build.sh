#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

mkdir -p bin

echo "==> Mengompilasi Device Frame Overlay dylib..."
clang -arch arm64 -arch arm64e -dynamiclib -O2 -fobjc-arc -framework Cocoa -framework CoreGraphics -framework QuartzCore src/frame/DeviceFrameOverlay.m -o bin/libUniversalControlFrame.dylib

echo "==> Mengompilasi UniversalADBControlDisplay helper binary..."
clang -arch arm64 -arch arm64e -O2 src/helper/UniversalADBControlDisplay.c -o bin/UniversalADBControlDisplay

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
swiftc -O -parse-as-library -target arm64-apple-macos26.0 \
    src/gui/LiquidGlass.swift \
    src/gui/AppState.swift \
    src/gui/MainView.swift \
    src/gui/main.swift \
    -o bin/UniversalADBControlGUI

echo "==> Sukses! Binary tersedia di folder bin/"
