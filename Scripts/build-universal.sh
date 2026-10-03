#!/bin/bash
# Build riêng hai kiến trúc rồi ghép thành một executable Universal.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
OUTPUT="${2:-build/universal/SubVoiceApp}"
SCRATCH="${SUBVOICE_BUILD_PATH:-.build}"
for architecture in arm64 x86_64; do
    swift build -c "$CONFIG" --product SubVoiceApp --arch "$architecture" --scratch-path "$SCRATCH"
done
ARM_BIN=$(swift build -c "$CONFIG" --arch arm64 --scratch-path "$SCRATCH" --show-bin-path)
INTEL_BIN=$(swift build -c "$CONFIG" --arch x86_64 --scratch-path "$SCRATCH" --show-bin-path)
mkdir -p "$(dirname "$OUTPUT")"
lipo -create "$ARM_BIN/SubVoiceApp" "$INTEL_BIN/SubVoiceApp" -output "$OUTPUT"
lipo "$OUTPUT" -verify_arch arm64 x86_64
lipo -archs "$OUTPUT"
