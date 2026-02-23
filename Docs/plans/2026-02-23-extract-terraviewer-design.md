# Extract TraceMacApp + TerraCLI into TerraViewer Repo

**Date:** 2026-02-23
**Status:** Approved

## Goal

Keep the Terra SDK repo focused on instrumentation by extracting the Mac viewer app and CLI into a new `TerraViewer` repository.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| TerraTraceKit location | Stays in Terra | It implements the terra.v1 contract — belongs with the SDK that produces spans |
| TerraCLI location | Moves with app | Groups all "viewer" tools together |
| Repo name | TerraViewer | Focused on the viewing/observability tooling |
| Git history | Fresh start | App is evolving rapidly; old history stays in Terra |
| TerraTraceKit consumption | Remote SPM dependency (Option A) | Prevents silent drift of OTLP decoder / contract validation |

## What Moves to TerraViewer

| Source (Terra repo) | Destination (TerraViewer repo) |
|---|---|
| `Sources/TraceMacApp/` (92 files — TraceMacAppUI) | `Sources/TraceMacApp/` |
| `Sources/TraceMacAppExecutable/` (1 file) | `Sources/TraceMacAppExecutable/` |
| `Sources/terra-cli/` (5 files) | `Sources/TerraCLI/` |
| `Tests/TraceMacAppTests/` (11 files) | `Tests/TraceMacAppTests/` |
| `Tests/TraceMacAppUITests/` (13 files) | `Tests/TraceMacAppUITests/` |
| `Apps/TraceMacApp/` (xcodeproj, entitlements, plist) | `Apps/TraceMacApp/` |
| Release scripts referencing TraceMacApp | `scripts/release/` |

## What Stays in Terra

- `Sources/TerraTraceKit/` — published as `.library` product
- `Tests/TerraTraceKitTests/` + fixtures
- All Terra SDK modules
- SDK CI, docs, telemetry convention

## TerraViewer Package.swift

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TerraViewer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/<org>/Terra.git", from: "1.0.0"),
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.3.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "TraceMacAppUI",
            dependencies: [
                .product(name: "TerraTraceKit", package: "Terra"),
                .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
                .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
            ],
            path: "Sources/TraceMacApp"
        ),
        .executableTarget(
            name: "TraceMacApp",
            dependencies: [
                "TraceMacAppUI",
                .product(name: "TerraTraceKit", package: "Terra"),
            ],
            path: "Sources/TraceMacAppExecutable"
        ),
        .executableTarget(
            name: "TerraCLI",
            dependencies: [
                .product(name: "TerraTraceKit", package: "Terra"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/TerraCLI"
        ),
        .testTarget(
            name: "TraceMacAppTests",
            dependencies: [
                "TraceMacAppUI",
                .product(name: "TerraTraceKit", package: "Terra"),
                .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
                .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
            ]
        ),
        .testTarget(
            name: "TraceMacAppUITests",
            dependencies: [
                "TraceMacAppUI",
                .product(name: "TerraTraceKit", package: "Terra"),
                .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
                .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
            ]
        ),
    ]
)
```

## Terra Package.swift Changes

Remove:
- `TraceMacApp` executable target
- `TraceMacAppUI` library target
- `TerraCLI` executable target
- `TraceMacAppTests` test target
- `TraceMacAppUITests` test target
- `swift-argument-parser` dependency

Keep:
- `TerraTraceKit` as public `.library` product
- `TerraTraceKitTests`
- All SDK targets unchanged

## Terra Repo Cleanup

Delete directories:
- `Sources/TraceMacApp/`
- `Sources/TraceMacAppExecutable/`
- `Sources/terra-cli/`
- `Tests/TraceMacAppTests/`
- `Tests/TraceMacAppUITests/`
- `Apps/TraceMacApp/`

Update:
- `CLAUDE.md` — remove TraceMacApp/CLI sections
- `.github/workflows/ci.yml` — remove app build/test jobs
- `Package.swift` — remove targets and unused dependency

## TerraViewer CI (New)

- SPM build + test (macOS 14+)
- Xcode unsigned build
- Release workflow: build, DMG, notarization (move scripts from Terra)
