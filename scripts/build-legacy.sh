#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/cache
cat Sources/AudioRecovery.swift AudioGuard.swift > build/legacy-main.swift
for ARCH in arm64 x86_64; do
 swiftc -O -module-cache-path build/cache -target "$ARCH-apple-macosx13.0" -framework AppKit build/legacy-main.swift -o "build/legacy-$ARCH"
done
lipo -create build/legacy-arm64 build/legacy-x86_64 -output ua-audio-guard
./ua-audio-guard --self-test-timing
