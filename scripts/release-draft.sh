#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(cat VERSION)"
gh release create "v$VERSION" "dist/IOGuard-$VERSION-universal.dmg" "dist/IOGuard-$VERSION-universal.dmg.sha256" --draft --title "IOGuard $VERSION" --notes-file "docs/RELEASE-NOTES-$VERSION.md" --target "$(git rev-parse HEAD)"
