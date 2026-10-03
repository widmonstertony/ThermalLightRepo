#!/bin/bash
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${1:-$SOURCE_DIR/../build}"
/bin/mkdir -p "$OUTPUT_DIR"
BUILD_PLATFORM="${NTF_BUILD_PLATFORM:-maccatalyst}"

if [[ "$BUILD_PLATFORM" == "ios" ]]; then
    SDK_NAME="iphoneos"
    TARGET_TRIPLE="arm64-apple-ios13.0"
    PLATFORM_ARGS=(-DNTF_IPAD_CAPABLE_BUILD=1)
elif [[ "$BUILD_PLATFORM" == "maccatalyst" ]]; then
    SDK_NAME="macosx"
    TARGET_TRIPLE="arm64-apple-ios14.0-macabi"
    SDK_ROOT="$(/usr/bin/xcrun --sdk "$SDK_NAME" --show-sdk-path)"
    PLATFORM_ARGS=(-iframework "$SDK_ROOT/System/iOSSupport/System/Library/Frameworks")
else
    echo "Unsupported NTF_BUILD_PLATFORM: $BUILD_PLATFORM" >&2
    exit 2
fi

SDK_ROOT="${SDK_ROOT:-$(/usr/bin/xcrun --sdk "$SDK_NAME" --show-sdk-path)}"

/usr/bin/xxd -i -n NTFVidCatchBridgeScriptBytes \
    "$SOURCE_DIR/VidCatchBridge.js" \
    > "$OUTPUT_DIR/VidCatchBridge.c"

/usr/bin/xcrun --sdk "$SDK_NAME" clang \
    -target "$TARGET_TRIPLE" \
    -isysroot "$SDK_ROOT" \
    "${PLATFORM_ARGS[@]}" \
    -dynamiclib \
    -fobjc-arc \
    -framework Foundation \
    -framework UIKit \
    -framework WebKit \
    -framework MediaPlayer \
    -framework AVFoundation \
    -framework CoreMedia \
    -framework CoreGraphics \
    -install_name '@executable_path/Frameworks/NewTWebFixV8.dylib' \
    "$SOURCE_DIR/NewTWebFix.m" \
    "$OUTPUT_DIR/VidCatchBridge.c" \
    -o "$OUTPUT_DIR/NewTWebFixV8.dylib"

/usr/bin/codesign --force --sign - "$OUTPUT_DIR/NewTWebFixV8.dylib"
echo "Built $OUTPUT_DIR/NewTWebFixV8.dylib"
