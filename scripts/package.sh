#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(cat VERSION)"
mkdir -p dist build/dmg-stage
STAGE="$PWD/build/dmg-stage"
# Recreate only the known packaging stage, never the project or a mounted volume.
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto build/IOGuard.app "$STAGE/IOGuard.app"
ln -s /Applications "$STAGE/Applications"
cp Assets/AppIcon.icns "$STAGE/.VolumeIcon.icns"
cp docs/INSTALL.txt "$STAGE/Read Me.txt"
RW="$PWD/build/IOGuard-installer.dmg"
DMG="$PWD/dist/IOGuard-$VERSION-universal.dmg"
hdiutil create -ov -volname IOGuard -srcfolder "$STAGE" -format UDRW "$RW"
MOUNT="$(mktemp -d /private/tmp/ioguard-dmg.XXXXXX)"
ATTACHED=0
cleanup() { if [ "$ATTACHED" = 1 ]; then hdiutil detach "$MOUNT" >/dev/null || true; fi; rmdir "$MOUNT" 2>/dev/null || true; }
trap cleanup EXIT
hdiutil attach "$RW" -nobrowse -mountpoint "$MOUNT"
ATTACHED=1
xcrun SetFile -a C "$MOUNT"
hdiutil detach "$MOUNT"
ATTACHED=0
hdiutil convert "$RW" -format UDZO -o "$DMG" -ov
# Custom artwork on the DMG file itself, as well as the mounted volume.
swift -module-cache-path "$PWD/build/cache" scripts/set-file-icon.swift Assets/AppIcon.png "$DMG"
if [ -n "${SIGNING_IDENTITY:-}" ]; then codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG"; fi
(cd dist && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "Packaged $DMG"
