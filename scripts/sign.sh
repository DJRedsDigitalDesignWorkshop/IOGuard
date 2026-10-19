#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to your Developer ID Application identity}"
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" build/IOGuard.app
codesign --verify --deep --strict --verbose=2 build/IOGuard.app
