#!/bin/bash
set -e

echo "Building FindMyFlipperMac..."
swift build -c release -Xswiftc -gnone
BUILD_DIR="$(swift build -c release --show-bin-path)"

clean_bundle_xattrs() {
  local target="$1"
  xattr -cr "$target" >/dev/null 2>&1 || true
  while IFS= read -r -d '' item; do
    xattr -c "$item" >/dev/null 2>&1 || true
    xattr -d com.apple.FinderInfo "$item" >/dev/null 2>&1 || true
    xattr -d com.apple.ResourceFork "$item" >/dev/null 2>&1 || true
    xattr -d 'com.apple.fileprovider.fpfs#P' "$item" >/dev/null 2>&1 || true
    xattr -d com.apple.macl "$item" >/dev/null 2>&1 || true
    xattr -d com.apple.provenance "$item" >/dev/null 2>&1 || true
  done < <(find "$target" -print0)
}

echo "Preparing Python backend runtime..."
if [ ! -x "Backend/venv/bin/python3" ]; then
  python3 -m venv Backend/venv
  Backend/venv/bin/python3 -m pip install --upgrade pip
  Backend/venv/bin/python3 -m pip install -r Backend/requirements.txt
fi

echo "Creating App Bundle..."
APP_DIR="FindMyFlipper.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Stopping any running app instance..."
osascript -e 'tell application "FindMyFlipper" to quit' >/dev/null 2>&1 &
QUIT_PID=$!
sleep 1
if kill -0 "$QUIT_PID" >/dev/null 2>&1; then
  kill "$QUIT_PID" >/dev/null 2>&1 || true
fi
wait "$QUIT_PID" >/dev/null 2>&1 || true
pkill -x FindMyFlipperMac >/dev/null 2>&1 || true
sleep 0.5

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp "$BUILD_DIR/FindMyFlipperMac" "$MACOS_DIR/"

# Copy SwiftPM resource bundle for bundled images and preview data.
rm -rf "$RESOURCES_DIR/FindMyFlipperMac_FindMyFlipperMac.bundle"
rm -rf "$APP_DIR/FindMyFlipperMac_FindMyFlipperMac.bundle"
if [ -d "$BUILD_DIR/FindMyFlipperMac_FindMyFlipperMac.bundle" ]; then
  cp -R "$BUILD_DIR/FindMyFlipperMac_FindMyFlipperMac.bundle" "$RESOURCES_DIR/"
fi
cp "Sources/FindMyFlipperMac/Resources/Assets.xcassets/FlipperZero.imageset/flipper-zero.png" \
  "$RESOURCES_DIR/flipper-zero.png"

echo "Creating app icon..."
ICON_SOURCE="Sources/FindMyFlipperMac/Resources/Assets.xcassets/FlipperZero.imageset/flipper-zero.png"
ICONSET_DIR="$RESOURCES_DIR/FindMyFlipper.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
sips -z 16 16     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/FindMyFlipper.icns"
rm -rf "$ICONSET_DIR"

echo "Bundling Python backend..."
rm -rf "$RESOURCES_DIR/Backend"
rsync -a \
  --exclude '__pycache__/' \
  --exclude '*.pyc' \
  --exclude '.pytest_cache/' \
  --exclude '.DS_Store' \
  --exclude 'venv/' \
  --exclude '.venv/' \
  --exclude 'FindMyFlipperRepo/' \
  Backend/ "$RESOURCES_DIR/Backend/"

# Build a fresh bundle-local runtime instead of copying the developer venv.
# Copying an existing venv can pull in absolute Homebrew/Python symlink trees
# and make local packaging slow or non-portable.
python3 -m venv --copies "$RESOURCES_DIR/Backend/venv"
"$RESOURCES_DIR/Backend/venv/bin/python3" -m pip install --upgrade pip >/dev/null
"$RESOURCES_DIR/Backend/venv/bin/python3" -m pip install -r "$RESOURCES_DIR/Backend/requirements.txt" >/dev/null

# Create full Info.plist with all required keys for macOS to accept the bundle
cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FindMyFlipperMac</string>
    <key>CFBundleIdentifier</key>
    <string>com.arxhsz.FindMyFlipperMac</string>
    <key>CFBundleName</key>
    <string>FindMyFlipper</string>
    <key>CFBundleDisplayName</key>
    <string>FindMyFlipper</string>
    <key>CFBundleIconFile</key>
    <string>FindMyFlipper</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>FindMyFlipper uses Bluetooth to scan for and reconnect to your Flipper Zero.</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>FindMyFlipper uses Bluetooth to scan for and reconnect to your Flipper Zero.</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

echo "Code signing the app bundle..."
clean_bundle_xattrs "$APP_DIR"
if codesign --force --deep --sign - "$APP_DIR"; then
  # Finder can add FinderInfo/resource-fork xattrs to local .app bundles. They
  # are not part of the signature payload and strict verification rejects them as
  # attached data, so clear them recursively after signing.
  clean_bundle_xattrs "$APP_DIR"
  codesign --verify --deep "$APP_DIR"
else
  echo "Warning: local ad-hoc signing failed, likely due protected macOS provenance metadata."
  echo "Continuing with an unsigned development bundle for local testing."
  rm -rf "$CONTENTS_DIR/_CodeSignature"
fi

echo "Stopping any previous Python backend server..."
# Kill any old backend on port 8765
lsof -ti:8765 | xargs kill -9 2>/dev/null || true

echo "App Bundle created and signed at $APP_DIR"
if [ "${FINDMYFLIPPER_SKIP_LAUNCH:-0}" = "1" ]; then
  echo "Launch skipped by FINDMYFLIPPER_SKIP_LAUNCH."
else
  echo "Launching app..."
  open "$APP_DIR"
  # LaunchServices can attach FinderInfo immediately after opening a local app.
  # Clear it again so the bundle remains strict-verification clean on disk.
  sleep 0.5
  clean_bundle_xattrs "$APP_DIR"
fi
