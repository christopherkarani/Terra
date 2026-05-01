# Platform Compatibility

Terra ships as a multi-platform Swift package, but not every component is
available on every Apple platform. This document explains the support matrix,
the `libtera` / `libterra` artifact naming, and how to enable additional
platform slices when they become available.

## Apple Platform Support Matrix

| Platform     | Swift-native modules | Zig-backed C ABI core (`TERRA_USE_ZIG_CORE`) |
|--------------|----------------------|----------------------------------------------|
| macOS 14+    | Supported            | Supported (current `libtera.xcframework` slice) |
| iOS 13+      | Supported            | Not yet packaged (see "Adding iOS slices" below) |
| tvOS 13+     | Supported            | Not yet packaged |
| watchOS 6+   | Supported            | Not yet packaged |
| visionOS 1+  | Supported            | Not yet packaged |

The Swift-native portions of Terra (manual tracing, workflow APIs, OpenTelemetry
glue, instrumentation modules) compile and run on every platform listed above.
The Zig-backed core is currently only vendored for macOS; the `CTerraBridge`
target in `Package.swift` is gated with
`condition: .when(platforms: [.macOS])` so non-macOS builds simply skip the
bridge and use the pure-Swift path.

The `TERRA_USE_ZIG_CORE` Swift compiler flag is also gated to macOS in
`Package.swift`. When you run on iOS / tvOS / watchOS / visionOS you get the
Swift-only path automatically — no source change required.

## `libtera` vs `libterra` Artifact Naming

Terra has two related-but-distinct artifact names that are easy to confuse:

- **`libterra`** — The canonical C library name. The Zig core under
  `zig-core/` builds `libterra.a` (and on Android `libterra.so`).
- **`libtera`** — The 5-letter form used inside the vendored Apple xcframework
  (`Vendor/libtera.xcframework`). The xcframework wraps `libterra.a` and
  re-exposes it under the `libtera` name so that the Swift `binaryTarget` name
  in `Package.swift` matches the framework directory.

The split is intentional aliasing for distribution:

1. Zig produces `libterra.a` (the canonical name).
2. The macOS xcframework wraps it as `libtera.a` so the Swift Package Manager
   `binaryTarget(name: "libtera", ...)` declaration matches a framework name
   that fits Apple's xcframework naming conventions.
3. The Android JNI build links Zig's `libterra.a` directly into `libtera.so`
   for `terra-android`.

This naming dual will be unified in a future release. For now, treat
`libtera` as "the macOS xcframework slice of `libterra`".

## Adding iOS / tvOS / watchOS / visionOS Slices to the xcframework

To enable the Zig-backed core on additional Apple platforms:

1. Update `Scripts/build-libtera-xcframework.sh` to build Zig with the
   appropriate iOS / tvOS / watchOS / visionOS device and simulator triples.
2. Run the script on a host that has the corresponding SDKs installed.
3. The script produces a refreshed `Vendor/libtera.xcframework` that contains
   slices for each requested platform.
4. Remove the `condition: .when(platforms: [.macOS])` guards on `CTerraBridge`
   and the `TERRA_USE_ZIG_CORE` define in `Package.swift` only after every
   target platform has a slice. Mixed availability should keep the macOS-only
   guard so non-macOS builds remain Swift-only.

The Swift-only path is the source of truth: the Zig core is an optional
optimization, and `Terra.start(_:)` is correct on every platform regardless of
whether the Zig path is compiled in.

## Recommended Host Platforms

- **Local development & CI** — macOS 14 or later (Apple Silicon recommended).
  This is the only host where the Zig-backed core is exercised end-to-end and
  where the xcframework can be rebuilt.
- **Application targets** — Any Apple platform listed in the matrix above.
  Apps that only use the Swift-native APIs (`Terra.start(_:)`, `Terra.workflow`,
  `Terra.startSpan`, etc.) deploy unchanged across iOS, tvOS, watchOS, and
  visionOS.
- **Cross-compilation** — Building Terra for iOS from macOS works via Xcode and
  SwiftPM as expected; the xcframework's missing iOS slice does not block the
  build because `CTerraBridge` is conditionally excluded.

## Related References

- `Package.swift` — platform declarations, `CTerraBridge` target, and the
  `libtera` binary target.
- `Sources/CTerraBridge/include/` — C header surface for the Zig core.
- `Scripts/build-libtera-xcframework.sh` — xcframework build pipeline.
- `Scripts/build-libtera-android.sh` — Android JNI build (linking
  `libterra.a` into `libtera.so`).
