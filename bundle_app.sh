#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

APP_NAME="Universal ADB Control"
BUNDLE_DIR="bin/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
HELPERS_DIR="${CONTENTS_DIR}/Helpers"

echo "==> Mengompilasi binary..."
./build.sh

echo "==> Membuat macOS App Bundle (${APP_NAME}.app)..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${HELPERS_DIR}"

cp bin/UniversalADBControlGUI "${MACOS_DIR}/UniversalADBControlGUI"
chmod +x "${MACOS_DIR}/UniversalADBControlGUI"

# Info.plist untuk aplikasi utama
cat << EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>UniversalADBControlGUI</string>
    <key>CFBundleIdentifier</key>
    <string>com.universal.adb.control.gui</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Menyiapkan UniversalADBControlDisplay helper bundle (pembungkus scrcpy)
# Berstatus LSUIElement agar scrcpy TIDAK PERNAH muncul sebagai aplikasi terpisah di Dock
SCRCPY_BIN="$(which scrcpy || echo "/opt/homebrew/bin/scrcpy")"
USER_HELPERS="$HOME/.universal-adb-control/helpers"
mkdir -p "$USER_HELPERS"

setup_display_bundle() {
    local target_app="$1"
    mkdir -p "${target_app}/Contents/MacOS"
    cat << EOF > "${target_app}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>UniversalADBControlDisplay</string>
    <key>CFBundleIdentifier</key>
    <string>com.universal.adb.control.display</string>
    <key>CFBundleName</key>
    <string>Universal ADB Control</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF
    rm -f "${target_app}/Contents/MacOS/UniversalADBControlDisplay"
    ln -sf "${SCRCPY_BIN}" "${target_app}/Contents/MacOS/UniversalADBControlDisplay"
}

setup_display_bundle "${HELPERS_DIR}/UniversalADBControlDisplay.app"
setup_display_bundle "${USER_HELPERS}/UniversalADBControlDisplay.app"

# Salin libUniversalControlFrame.dylib ke helpers
cp bin/libUniversalControlFrame.dylib "${USER_HELPERS}/libUniversalControlFrame.dylib"
mkdir -p "${CONTENTS_DIR}/Frameworks"
cp bin/libUniversalControlFrame.dylib "${CONTENTS_DIR}/Frameworks/libUniversalControlFrame.dylib"

echo "==> Sukses! Aplikasi macOS bundle siap di ${BUNDLE_DIR}"
echo "    Bisa dibuka dengan: open \"${BUNDLE_DIR}\""
