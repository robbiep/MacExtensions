#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
NAME="MissionControlPlus"
BUNDLE_ID="com.robbieperlstein.MissionControlPlus"
VERSION="0.1.0"
OUT="build/${NAME}.app"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/${NAME}"

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/${NAME}"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleName</key><string>Mission Control Plus</string>
  <key>CFBundleDisplayName</key><string>MissionControlPlus</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>${NAME}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
echo -n "APPL????" > "$OUT/Contents/PkgInfo"

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -o '"Apple Development: [^"]*"' | tr -d '"' || true)"
  SIGN_IDENTITY="${SIGN_IDENTITY:--}"
fi

codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" --options runtime "$OUT" 2>/dev/null || \
  codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$OUT"

codesign -dv "$OUT" 2>&1 | grep -E 'Identifier|Authority|Signature' | head -5 || true
echo "Built: $PWD/$OUT (signed with: $SIGN_IDENTITY)"
