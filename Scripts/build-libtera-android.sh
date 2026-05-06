#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ZIG_CORE="$ROOT_DIR/zig-core"
ANDROID_DIR="$ROOT_DIR/terra-android"
JNI_DIR="$ANDROID_DIR/jni"
OUTPUT_DIR="$ANDROID_DIR/jniLibs"
NDK_BUILD_DIR="$ANDROID_DIR/.ndk-build"
ANDROID_API_LEVEL="${ANDROID_API_LEVEL:-34}"
ANDROID_MIN_SDK="${ANDROID_MIN_SDK:-26}"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}}"
ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-}"

if [[ -z "$ANDROID_NDK_ROOT" ]]; then
    if [[ -d "$ANDROID_SDK_ROOT/ndk" ]]; then
        latest_ndk="$(find "$ANDROID_SDK_ROOT/ndk" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)"
        ANDROID_NDK_ROOT="${latest_ndk:-}"
    fi
fi

if [[ -z "$ANDROID_NDK_ROOT" || ! -x "$ANDROID_NDK_ROOT/ndk-build" ]]; then
    echo "error: Android NDK not found. Set ANDROID_NDK_ROOT or install an NDK under $ANDROID_SDK_ROOT/ndk" >&2
    exit 1
fi

# Clean previous builds
rm -rf "$OUTPUT_DIR"
rm -rf "$NDK_BUILD_DIR"
rm -rf "$JNI_DIR/arm64-v8a" "$JNI_DIR/x86_64"

# Map: zig_target:android_abi
TARGETS=(
    "aarch64-linux-android.${ANDROID_API_LEVEL}:arm64-v8a"
    "x86_64-linux-android.${ANDROID_API_LEVEL}:x86_64"
)

for target_abi in "${TARGETS[@]}"; do
    IFS=':' read -r zig_target abi <<< "$target_abi"
    echo "Building Zig static core for $abi ($zig_target)..."
    mkdir -p "$JNI_DIR/$abi"
    mkdir -p "$OUTPUT_DIR/$abi"
    (
        cd "$ZIG_CORE"
        rm -rf zig-out .zig-cache
        zig build -Dtarget="$zig_target" -Doptimize=ReleaseFast
        cp "zig-out/lib/libterra.a" "$JNI_DIR/$abi/libtera.a"
    )
    echo "Linking JNI bridge for $abi with ndk-build..."
    (
        cd "$ANDROID_DIR"
        "$ANDROID_NDK_ROOT/ndk-build" \
            NDK_PROJECT_PATH=. \
            APP_BUILD_SCRIPT=jni/Android.mk \
            NDK_OUT="$NDK_BUILD_DIR/$abi/obj" \
            NDK_LIBS_OUT="$OUTPUT_DIR" \
            APP_ABI="$abi" \
            APP_PLATFORM="android-${ANDROID_MIN_SDK}"
    )
    rm -rf "$JNI_DIR/$abi"
    echo "  -> $OUTPUT_DIR/$abi/libtera.so"
done

rm -rf "$NDK_BUILD_DIR"

echo ""
echo "Done. Libraries in $OUTPUT_DIR:"
find "$OUTPUT_DIR" -name "*.so" -exec file {} \;
