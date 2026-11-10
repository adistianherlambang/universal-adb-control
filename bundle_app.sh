#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

APP_NAME="Universal ADB Control"
BUNDLE_DIR="bin/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> Mengompilasi binary..."
./build.sh

echo "==> Membuat macOS App Bundle (${APP_NAME}.app)..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp bin/UniversalADBControlGUI "${MACOS_DIR}/UniversalADBControlGUI"
chmod +x "${MACOS_DIR}/UniversalADBControlGUI"

# Info.plist
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

echo "==> Sukses! Aplikasi macOS bundle siap di ${BUNDLE_DIR}"
echo "    Bisa dibuka dengan: open \"${BUNDLE_DIR}\""
