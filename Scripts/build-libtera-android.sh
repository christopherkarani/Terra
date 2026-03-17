#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ZIG_CORE="$ROOT_DIR/zig-core"
OUTPUT_DIR="$ROOT_DIR/terra-android/jniLibs"

# Clean previous builds
rm -rf "$OUTPUT_DIR"

# Map: zig_target:android_abi
TARGETS=(
    "aarch64-linux-android:arm64-v8a"
    "x86_64-linux-android:x86_64"
)

for target_abi in "${TARGETS[@]}"; do
    IFS=':' read -r zig_target abi <<< "$target_abi"
    echo "Building for $abi ($zig_target)..."
    mkdir -p "$OUTPUT_DIR/$abi"
    (
        cd "$ZIG_CORE"
        zig build -Dtarget="$zig_target" -Doptimize=ReleaseFast
        cp "zig-out/lib/libterra_shared.so" "$OUTPUT_DIR/$abi/libtera.so"
    )
    echo "  -> $OUTPUT_DIR/$abi/libtera.so"
done

echo ""
echo "Done. Libraries in $OUTPUT_DIR:"
find "$OUTPUT_DIR" -name "*.so" -exec file {} \;
