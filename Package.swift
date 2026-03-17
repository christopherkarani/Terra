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
    .library(name: "TerraHTTPInstrument", targets: ["TerraHTTPInstrument"]),
    .library(name: "TerraFoundationModels", targets: ["TerraFoundationModels"]),
    .library(name: "TerraMLX", targets: ["TerraMLX"]),
    .library(name: "TerraMetalProfiler", targets: ["TerraMetalProfiler"]),
    .library(name: "TerraSystemProfiler", targets: ["TerraSystemProfiler"]),
    .library(name: "TerraAccelerate", targets: ["TerraAccelerate"]),
    .library(name: "TerraTracedMacro", targets: ["TerraTracedMacro"]),
    .executable(name: "TerraSample", targets: ["TerraSample"]),
    .executable(name: "TerraSDKBenchmarks", targets: ["TerraSDKBenchmarks"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.25.0"),
    .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.3.0"),
    .package(url: "https://github.com/open-telemetry/opentelemetry-swift.git", from: "2.3.0"),
    .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0")
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
      path: "Sources/Terra",
      exclude: ["CLAUDE.md"]
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
      path: "Sources/TerraCoreML",
      exclude: ["CLAUDE.md"]
    ),
    .target(
      name: "TerraTraceKit",
      dependencies: [
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetryProtocolExporter", package: "opentelemetry-swift")
      ],
      path: "Sources/TerraTraceKit",
      exclude: ["CLAUDE.md"]
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
      path: "Sources/TerraAutoInstrument",
      exclude: ["CLAUDE.md"]
    ),
    .target(
      name: "TerraHTTPInstrument",
      dependencies: [
        "TerraCore",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "URLSessionInstrumentation", package: "opentelemetry-swift"),
      ],
      path: "Sources/TerraHTTPInstrument",
      exclude: ["CLAUDE.md"]
    ),
    .target(
      name: "TerraFoundationModels",
      dependencies: [
        "TerraCore",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
      ],
      path: "Sources/TerraFoundationModels",
      exclude: ["CLAUDE.md"]
    ),
    .target(
      name: "TerraMLX",
      dependencies: [
        "TerraCore",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
      ],
      path: "Sources/TerraMLX",
      exclude: ["CLAUDE.md"]
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
    .executableTarget(
      name: "TerraSDKBenchmarks",
      dependencies: [
        "Terra",
        "TerraCore",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "InMemoryExporter", package: "opentelemetry-swift"),
      ],
      path: "Benchmarks/TerraSDKBenchmarks"
    ),

    // MARK: - @Traced Macro

    .macro(
      name: "TerraTracedMacroPlugin",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "SwiftDiagnostics", package: "swift-syntax"),
      ],
      path: "Sources/TerraTracedMacroPlugin",
      exclude: ["CLAUDE.md"]
    ),
    .target(
      name: "TerraTracedMacro",
      dependencies: [
        "TerraTracedMacroPlugin",
        "TerraCore",
      ],
      path: "Sources/TerraTracedMacro",
      exclude: ["CLAUDE.md"]
    ),

    // MARK: - Test Targets

    .testTarget(
      name: "TerraTests",
      dependencies: [
        "TerraCore",
        "TerraLlama",
        "TerraTraceKit",
        .product(name: "InMemoryExporter", package: "opentelemetry-swift"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
      ],
      path: "Tests/TerraTests",
      exclude: ["CLAUDE.md"]
    ),
    .testTarget(
      name: "TerraCoreMLTests",
      dependencies: [
        "TerraCoreML",
        "TerraCore",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "InMemoryExporter", package: "opentelemetry-swift"),
      ],
      path: "Tests/TerraCoreMLTests",
      exclude: ["CLAUDE.md"]
    ),
    .testTarget(
      name: "TerraTraceKitTests",
      dependencies: [
        "TerraTraceKit",
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
      ],
      path: "Tests/TerraTraceKitTests",
      exclude: ["CLAUDE.md"]
    ),
    .testTarget(
      name: "TerraHTTPInstrumentTests",
      dependencies: [
        "TerraHTTPInstrument",
        "TerraCore",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "InMemoryExporter", package: "opentelemetry-swift"),
      ],
      path: "Tests/TerraHTTPInstrumentTests",
      exclude: ["CLAUDE.md"]
    ),
    .testTarget(
      name: "TerraMLXTests",
      dependencies: [
        "TerraMLX",
        "TerraCore",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "InMemoryExporter", package: "opentelemetry-swift"),
      ],
      path: "Tests/TerraMLXTests",
      exclude: ["CLAUDE.md"]
    ),
    .testTarget(
      name: "TerraAutoInstrumentTests",
      dependencies: [
        "Terra",
        "TerraCore",
        "TerraCoreML",
        "TerraMetalProfiler",
        "TerraSystemProfiler",
        "TerraTraceKit",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "InMemoryExporter", package: "opentelemetry-swift"),
      ],
      path: "Tests/TerraAutoInstrumentTests",
      exclude: ["CLAUDE.md"]
    ),
    .testTarget(
      name: "TerraFoundationModelsTests",
      dependencies: [
        "TerraFoundationModels",
        "TerraCore",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "InMemoryExporter", package: "opentelemetry-swift"),
      ],
      path: "Tests/TerraFoundationModelsTests",
      exclude: ["CLAUDE.md"]
    ),
    .testTarget(
      name: "TerraTracedMacroTests",
      dependencies: [
        "TerraTracedMacroPlugin",
        "TerraTracedMacro",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "InMemoryExporter", package: "opentelemetry-swift"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
      ],
      path: "Tests/TerraTracedMacroTests",
      exclude: ["CLAUDE.md"]
    ),

    // MARK: - Examples

    .executableTarget(
      name: "TerraSample",
      dependencies: ["Terra"],
      path: "Examples/Terra Sample"
    )
  ]
)
