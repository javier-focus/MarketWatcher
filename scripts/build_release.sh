#!/usr/bin/env bash
# =============================================================================
# build_release.sh — MarketWatcher release build & DMG packager
#
# Usage (from repository root):
#   chmod +x scripts/build_release.sh
#   ./scripts/build_release.sh
#
# Output:
#   ./build/MarketWatcher.dmg
#
# Requirements:
#   - Xcode command-line tools installed  (xcode-select --install)
#   - Swift 5.9+  (ships with Xcode 15)
# =============================================================================

set -euo pipefail

# ── Paths ────────────────────────────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="${REPO_ROOT}/MarketWatcher"
BUILD_DIR="${REPO_ROOT}/build"
APP_DIR="${BUILD_DIR}/MarketWatcher.app"
DMG_PATH="${BUILD_DIR}/MarketWatcher.dmg"
INFO_PLIST="${PKG_DIR}/Sources/SP500Widget/App/Info.plist"

echo "============================================="
echo "  MarketWatcher — Release Build"
echo "============================================="
echo ""

# ── 1. Clean ─────────────────────────────────────────────────────────────────

echo "🧹  Cleaning previous build artifacts..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
echo "    Done."
echo ""

# ── 2. Compile (Release) ─────────────────────────────────────────────────────

echo "🔨  Building in Release configuration..."
cd "${PKG_DIR}"
swift build -c release --product MarketWatcherApp 2>&1 \
    | grep -v "^Build complete" \
    | grep -E "(error:|warning:|Build)" || true

BINARY_PATH="${PKG_DIR}/.build/release/MarketWatcherApp"
if [ ! -f "${BINARY_PATH}" ]; then
    echo "❌  Build failed — binary not found at ${BINARY_PATH}"
    exit 1
fi
echo "    Binary → ${BINARY_PATH}"
echo ""

# ── 3. Assemble .app bundle ──────────────────────────────────────────────────
#
# macOS .app bundle layout:
#   MarketWatcher.app/
#     Contents/
#       Info.plist          ← bundle metadata (CFBundleIdentifier etc.)
#       MacOS/
#         MarketWatcherApp  ← compiled executable
#       Resources/          ← asset catalog output (icons, etc.)

echo "📁  Assembling .app bundle..."

CONTENTS="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy executable
cp "${BINARY_PATH}" "${MACOS_DIR}/MarketWatcherApp"

# Copy Info.plist
if [ -f "${INFO_PLIST}" ]; then
    cp "${INFO_PLIST}" "${CONTENTS}/Info.plist"
else
    # Generate a minimal Info.plist if the source file was removed
    cat > "${CONTENTS}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>      <string>com.yourname.marketwatcher</string>
    <key>CFBundleName</key>            <string>MarketWatcher</string>
    <key>CFBundleDisplayName</key>     <string>MarketWatcher</string>
    <key>CFBundleExecutable</key>      <string>MarketWatcherApp</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>LSUIElement</key>             <true/>
</dict>
</plist>
PLIST
fi

# Copy compiled asset catalog resources (icons) if present
RESOURCES_BUILD="${PKG_DIR}/.build/release/MarketWatcher_MarketWatcher.bundle/Contents/Resources"
if [ -d "${RESOURCES_BUILD}" ]; then
    cp -R "${RESOURCES_BUILD}/." "${RESOURCES_DIR}/"
    echo "    Resources copied from bundle."
fi

echo "    .app → ${APP_DIR}"
echo ""

# ── 4. Ad-hoc code sign ──────────────────────────────────────────────────────
# Ad-hoc signing (-) is sufficient for local use. Replace with your Developer
# ID identity for distribution: e.g. "Developer ID Application: Your Name (XXXXXXX)"

echo "🔏  Ad-hoc code signing..."
codesign --force --deep --sign - "${APP_DIR}"
echo "    Signed."
echo ""

# ── 5. Create DMG ────────────────────────────────────────────────────────────

echo "💿  Creating DMG..."
rm -f "${DMG_PATH}"
hdiutil create \
    -volname   "MarketWatcher" \
    -srcfolder "${APP_DIR}" \
    -ov \
    -format    UDZO \
    "${DMG_PATH}"

if [ ! -f "${DMG_PATH}" ]; then
    echo "❌  DMG creation failed."
    exit 1
fi

# ── 6. Report ────────────────────────────────────────────────────────────────

DMG_SIZE=$(du -sh "${DMG_PATH}" | awk '{print $1}')
echo ""
echo "============================================="
echo "  ✅  Build complete!"
echo "  📂  ${DMG_PATH}  (${DMG_SIZE})"
echo "============================================="
echo ""
echo "To distribute: share MarketWatcher.dmg."
echo "Recipients open the DMG and drag MarketWatcher.app to Applications."
echo ""
