#!/usr/bin/env bash
# build-libtera-xcframework.sh
#
# Compiles libtera.a from zig-core for macOS (aarch64 + x86_64),
# merges the slices with lipo, and packages the result into
# Vendor/libtera.xcframework/.
#
# Usage:
#   ./Scripts/build-libtera-xcframework.sh [--release]
#
# Prerequisites:
#   - Zig 0.13+ on PATH
#   - Xcode command-line tools (for lipo, xcodebuild)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ZIG_CORE="$PROJECT_ROOT/zig-core"
VENDOR_DIR="$PROJECT_ROOT/Vendor"
XCFRAMEWORK_DIR="$VENDOR_DIR/libtera.xcframework"
BUILD_DIR="$PROJECT_ROOT/.build-xcframework"

# Parse flags
OPTIMIZE="ReleaseSafe"
if [[ "${1:-}" == "--release" ]]; then
  OPTIMIZE="ReleaseFast"
fi

echo "==> Building libtera for macOS (aarch64 + x86_64)"
echo "    Optimize: $OPTIMIZE"
echo "    Zig core: $ZIG_CORE"

# Clean previous build artifacts
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/aarch64-macos" "$BUILD_DIR/x86_64-macos" "$BUILD_DIR/macos-universal"

# ── Build aarch64-macos ──────────────────────────────────────────────────
echo "==> Compiling aarch64-macos..."
(cd "$ZIG_CORE" && zig build \
  -Dtarget=aarch64-macos \
  -Doptimize="$OPTIMIZE" \
  --prefix "$BUILD_DIR/aarch64-macos" \
)

# ── Build x86_64-macos ──────────────────────────────────────────────────
echo "==> Compiling x86_64-macos..."
(cd "$ZIG_CORE" && zig build \
  -Dtarget=x86_64-macos \
  -Doptimize="$OPTIMIZE" \
  --prefix "$BUILD_DIR/x86_64-macos" \
)

# ── Merge with lipo ─────────────────────────────────────────────────────
echo "==> Creating universal binary with lipo..."
lipo -create \
  "$BUILD_DIR/aarch64-macos/lib/libterra.a" \
  "$BUILD_DIR/x86_64-macos/lib/libterra.a" \
  -output "$BUILD_DIR/macos-universal/libtera.a"

# Verify the fat binary
echo "==> Verifying universal binary:"
lipo -info "$BUILD_DIR/macos-universal/libtera.a"

# ── Package as xcframework ───────────────────────────────────────────────
echo "==> Creating xcframework at $XCFRAMEWORK_DIR..."
rm -rf "$XCFRAMEWORK_DIR"
mkdir -p "$VENDOR_DIR"

xcodebuild -create-xcframework \
  -library "$BUILD_DIR/macos-universal/libtera.a" \
  -headers "$ZIG_CORE/include" \
  -output "$XCFRAMEWORK_DIR"

echo "==> Done. XCFramework created at:"
echo "    $XCFRAMEWORK_DIR"

# ── Cleanup ──────────────────────────────────────────────────────────────
rm -rf "$BUILD_DIR"

echo "==> Build complete."
