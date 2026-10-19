#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
VERSION="$(cat VERSION)"
APP="$ROOT/build/IOGuard.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/build/cache"
for ARCH in arm64 x86_64; do
  swiftc -O -module-cache-path "$ROOT/build/cache" -target "${ARCH}-apple-macosx13.0" -framework Cocoa -framework CoreAudio -framework ServiceManagement Sources/IOGuard.swift -o "$ROOT/build/IOGuard-$ARCH"
done
lipo -create "$ROOT/build/IOGuard-arm64" "$ROOT/build/IOGuard-x86_64" -output "$APP/Contents/MacOS/IOGuard"
cp Assets/AppIcon.icns Assets/MenuBarIconTemplate*.png "$APP/Contents/Resources/"
python3 - "$APP/Contents/Info.plist" "$VERSION" <<'PY'
import plistlib,sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({
 'CFBundleIdentifier':'com.djred.IOGuard','CFBundleName':'IOGuard',
 'CFBundleDisplayName':'IOGuard','CFBundleExecutable':'IOGuard',
 'CFBundlePackageType':'APPL','CFBundleShortVersionString':sys.argv[2],
 'CFBundleVersion':sys.argv[2],'CFBundleIconFile':'AppIcon',
 'LSMinimumSystemVersion':'13.0','LSUIElement':True,
 'NSHighResolutionCapable':True,'NSHumanReadableCopyright':'Copyright © 2026 djred',
}))
PY
codesign --force --sign - "$APP"
echo "Built $APP ($VERSION, Apple Silicon + Intel)"
