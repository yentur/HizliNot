#!/bin/bash
# Build HizliNot and package it into a double-clickable HizliNot.app
set -e
cd "$(dirname "$0")"

APP="HizliNot.app"
BIN_NAME="HizliNot"

echo "▶ Compiling (release)…"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$BIN_NAME"

echo "▶ Assembling $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Hızlı Not</string>
  <key>CFBundleDisplayName</key><string>Hızlı Not</string>
  <key>CFBundleExecutable</key><string>HizliNot</string>
  <key>CFBundleIdentifier</key><string>com.omer.hizlinot</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS lets it run / register the global hotkey without fuss
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

# Install into /Applications so it shows in Launchpad / Spotlight / Applications folder
DEST="/Applications/$APP"
if rm -rf "$DEST" 2>/dev/null && cp -R "$APP" "$DEST" 2>/dev/null; then
  echo "✅ Installed to $DEST"
  echo "   Launch from Launchpad/Spotlight as “Hızlı Not”, or:  open \"$DEST\""
else
  echo "✅ Built $APP (could not write to /Applications — run from here)"
  echo "   Run with:  open \"$(pwd)/$APP\""
fi
