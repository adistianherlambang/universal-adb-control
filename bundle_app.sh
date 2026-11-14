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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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
    <string>26.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

if [ -f "assets/AppIcon.icns" ]; then
    cp assets/AppIcon.icns "${RESOURCES_DIR}/AppIcon.icns"
fi
if [ -f "assets/adbLogo.png" ]; then
    cp assets/adbLogo.png "${RESOURCES_DIR}/adbLogo.png"
fi

# Menyiapkan UniversalADBControlDisplay helper bundle
USER_HELPERS="$HOME/.universal-adb-control/helpers"
mkdir -p "$USER_HELPERS"

setup_display_bundle() {
    local target_app="$1"
    mkdir -p "${target_app}/Contents/MacOS" "${target_app}/Contents/Resources"
    cat << EOF > "${target_app}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>UniversalADBControlDisplay</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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
    cp bin/UniversalADBControlDisplay "${target_app}/Contents/MacOS/UniversalADBControlDisplay"
    chmod +x "${target_app}/Contents/MacOS/UniversalADBControlDisplay"
    if [ -f "assets/AppIcon.icns" ]; then
        cp assets/AppIcon.icns "${target_app}/Contents/Resources/AppIcon.icns"
    fi
}

setup_display_bundle "${HELPERS_DIR}/UniversalADBControlDisplay.app"
setup_display_bundle "${USER_HELPERS}/UniversalADBControlDisplay.app"

# Salin libUniversalControlFrame.dylib ke helpers & frameworks
cp bin/libUniversalControlFrame.dylib "${USER_HELPERS}/libUniversalControlFrame.dylib"
mkdir -p "${CONTENTS_DIR}/Frameworks"
cp bin/libUniversalControlFrame.dylib "${CONTENTS_DIR}/Frameworks/libUniversalControlFrame.dylib"

# Perbarui salinan di /Applications agar macOS menemukan versi terbaru
rm -rf "/Applications/${APP_NAME}.app"
cp -R "${BUNDLE_DIR}" "/Applications/${APP_NAME}.app" 2>/dev/null || true

echo "==> Sukses! Aplikasi macOS bundle siap di ${BUNDLE_DIR}"
echo "    Bisa dibuka dengan: open \"${BUNDLE_DIR}\""
