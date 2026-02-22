// swift-tools-version:5.9
import PackageDescription
import CompilerPluginSupport

let package = Package(
  name: "Terra",
  platforms: [
    .macOS(.v14),
    .iOS(.v13),
    .tvOS(.v13),
    .watchOS(.v6),
    .visionOS(.v1)
  ],
  products: [
    .library(name: "Terra", targets: ["Terra"]),
    .library(name: "TerraCore", targets: ["TerraCore"]),
    .library(name: "TerraCoreML", targets: ["TerraCoreML"]),
    .library(name: "TerraTraceKit", targets: ["TerraTraceKit"]),
    .library(name: "TerraHTTPInstrument", targets: ["TerraHTTPInstrument"]),
    .library(name: "TerraFoundationModels", targets: ["TerraFoundationModels"]),
    .library(name: "TerraMLX", targets: ["TerraMLX"]),
    .library(name: "TerraMetalProfiler", targets: ["TerraMetalProfiler"]),
    .library(name: "TerraSystemProfiler", targets: ["TerraSystemProfiler"]),
    .library(name: "TerraLlama", targets: ["TerraLlama"]),
    .library(name: "TerraAccelerate", targets: ["TerraAccelerate"]),
    .library(name: "TerraTracedMacro", targets: ["TerraTracedMacro"]),
    .executable(name: "TerraSample", targets: ["TerraSample"])
  ],
  dependencies: [
    .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.3.0"),
    .package(url: "https://github.com/open-telemetry/opentelemetry-swift.git", from: "2.3.0"),
    .package(url: "https://github.com/apple/swift-crypto.git", from: "4.2.0"),
    .package(url: "https://github.com/apple/swift-testing.git", from: "0.99.0"),
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
  ],
  targets: [
    // MARK: - Core Libraries

    .target(
      name: "TerraCore",
      dependencies: [
        "TerraSystemProfiler",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetryProtocolExporterHTTP", package: "opentelemetry-swift"),
        .product(name: "PersistenceExporter", package: "opentelemetry-swift"),
        .product(name: "Sessions", package: "opentelemetry-swift"),
        .product(name: "Crypto", package: "swift-crypto"),
        .product(
          name: "SignPostIntegration",
          package: "opentelemetry-swift",
          condition: .when(platforms: [.iOS, .macOS, .tvOS, .watchOS, .visionOS])
        )
      ],
      path: "Sources/Terra"
    ),
    .target(
      name: "TerraCoreML",
      dependencies: [
        "TerraCore",
        "TerraMetalProfiler",
        "TerraSystemProfiler",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
      ],
      path: "Sources/TerraCoreML"
    ),
    .target(
      name: "TerraTraceKit",
      dependencies: [
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
      ],
      path: "Sources/TerraTraceKit"
    ),

    // MARK: - Auto-Instrumentation Umbrella

    .target(
      name: "Terra",
      dependencies: [
        "TerraCore",
        "TerraCoreML",
        "TerraHTTPInstrument",
        "TerraMetalProfiler",
        "TerraSystemProfiler",
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
      ],
      path: "Sources/TerraAutoInstrument"
    ),
    .target(
      name: "TerraHTTPInstrument",
      dependencies: [
        "TerraCore",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "URLSessionInstrumentation", package: "opentelemetry-swift"),
      ],
      path: "Sources/TerraHTTPInstrument"
    ),
    .target(
      name: "TerraFoundationModels",
      dependencies: [
        "TerraCore",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
      ],
      path: "Sources/TerraFoundationModels"
    ),
    .target(
      name: "TerraMLX",
      dependencies: [
        "TerraCore",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
      ],
      path: "Sources/TerraMLX"
    ),
    .target(
      name: "TerraMetalProfiler",
      dependencies: [
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
      ],
      path: "Sources/TerraMetalProfiler"
    ),
    .target(
      name: "TerraSystemProfiler",
      dependencies: [
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
      ],
      path: "Sources/TerraSystemProfiler"
    ),
    .target(
      name: "TerraLlama",
      dependencies: [
        "TerraCore",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
      ],
      path: "Sources/TerraLlama"
    ),
    .target(
      name: "TerraAccelerate",
      dependencies: [
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
      ],
      path: "Sources/TerraAccelerate"
    ),

    // MARK: - @Traced Macro

    .macro(
      name: "TerraTracedMacroPlugin",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
      ],
      path: "Sources/TerraTracedMacroPlugin"
    ),
    .target(
      name: "TerraTracedMacro",
      dependencies: [
        "TerraTracedMacroPlugin",
        "TerraCore",
      ],
      path: "Sources/TerraTracedMacro"
    ),

    // MARK: - TraceMacApp UI

    .target(
      name: "TraceMacAppUI",
      dependencies: [
        "TerraTraceKit",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
      ],
      path: "Sources/TraceMacApp",
      exclude: ["TraceMacApp.swift"]
    ),

    // MARK: - Test Targets

    .testTarget(
      name: "TerraTests",
      dependencies: [
        "TerraCore",
        "TerraTraceKit",
        .product(name: "InMemoryExporter", package: "opentelemetry-swift"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core")
      ],
      path: "Tests/TerraTests"
    ),
    .testTarget(
      name: "TerraCoreMLTests",
      dependencies: [
        "TerraCoreML",
        "TerraCore",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "InMemoryExporter", package: "opentelemetry-swift"),
        .product(name: "Testing", package: "swift-testing"),
      ],
      path: "Tests/TerraCoreMLTests"
    ),
    .testTarget(
      name: "TerraTraceKitTests",
      dependencies: [
        "TerraTraceKit",
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "Testing", package: "swift-testing"),
      ],
      path: "Tests/TerraTraceKitTests"
    ),
    .testTarget(
      name: "TerraHTTPInstrumentTests",
      dependencies: [
        "TerraHTTPInstrument",
        "TerraCore",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "InMemoryExporter", package: "opentelemetry-swift"),
        .product(name: "Testing", package: "swift-testing"),
      ],
      path: "Tests/TerraHTTPInstrumentTests"
    ),
    .testTarget(
      name: "TerraMLXTests",
      dependencies: [
        "TerraMLX",
        "TerraCore",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "InMemoryExporter", package: "opentelemetry-swift"),
        .product(name: "Testing", package: "swift-testing"),
      ],
      path: "Tests/TerraMLXTests"
    ),
    .testTarget(
      name: "TerraAutoInstrumentTests",
      dependencies: [
        "Terra",
        "TerraCore",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "InMemoryExporter", package: "opentelemetry-swift"),
        .product(name: "Testing", package: "swift-testing"),
      ],
      path: "Tests/TerraAutoInstrumentTests"
    ),
    .testTarget(
      name: "TerraFoundationModelsTests",
      dependencies: [
        "TerraFoundationModels",
        "TerraCore",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "InMemoryExporter", package: "opentelemetry-swift"),
        .product(name: "Testing", package: "swift-testing"),
      ],
      path: "Tests/TerraFoundationModelsTests"
    ),
    .testTarget(
      name: "TerraTracedMacroTests",
      dependencies: [
        "TerraTracedMacroPlugin",
        "TerraTracedMacro",
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
        .product(name: "Testing", package: "swift-testing"),
      ],
      path: "Tests/TerraTracedMacroTests"
    ),
    .testTarget(
      name: "TraceMacAppTests",
      dependencies: [
        "TerraTraceKit",
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "Testing", package: "swift-testing"),
      ],
      path: "Tests/TraceMacAppTests"
    ),
    .testTarget(
      name: "TraceMacAppUITests",
      dependencies: [
        "TraceMacAppUI",
        "TerraTraceKit",
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "Testing", package: "swift-testing"),
      ],
      path: "Tests/TraceMacAppUITests"
    ),

    // MARK: - Examples

    .executableTarget(
      name: "TerraSample",
      dependencies: ["Terra"],
      path: "Examples/Terra Sample"
    ),
    .executableTarget(
      name: "TerraCLI",
      dependencies: [
        "TerraTraceKit",
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ],
      path: "Sources/terra-cli"
    ),
    .executableTarget(
      name: "TraceMacApp",
      dependencies: ["TerraTraceKit"],
      path: "Sources/TraceMacApp"
    )
  ]
)
