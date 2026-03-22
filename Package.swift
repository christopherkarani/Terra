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
    .library(name: "TerraAccelerate", targets: ["TerraAccelerate"]),
    .library(name: "TerraPowerProfiler", targets: ["TerraPowerProfiler"]),
    .library(name: "TerraANEProfiler", targets: ["TerraANEProfiler"]),
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
    // MARK: - Zig Core (C ABI bridge)

    .target(
      name: "CTerraBridge",
      dependencies: ["libtera"],
      path: "Sources/CTerraBridge",
      publicHeadersPath: "include",
      linkerSettings: [
        .linkedLibrary("c++"),
      ]
    ),
    .binaryTarget(
      name: "libtera",
      path: "Vendor/libtera.xcframework"
    ),

    // MARK: - Core Libraries

    .target(
      name: "TerraCore",
      dependencies: [
        "TerraSystemProfiler",
        .target(name: "CTerraBridge", condition: .when(platforms: [.macOS])),
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
      swiftSettings: [
        .define("TERRA_USE_ZIG_CORE", .when(platforms: [.macOS])),
      ]
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
    ),
    .target(
      name: "TerraTraceKit",
      dependencies: [
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetryProtocolExporter", package: "opentelemetry-swift")
      ],
      path: "Sources/TerraTraceKit",
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
    ),
    .target(
      name: "TerraFoundationModels",
      dependencies: [
        "TerraCore",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
      ],
      path: "Sources/TerraFoundationModels",
    ),
    .target(
      name: "TerraMLX",
      dependencies: [
        "TerraCore",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
      ],
      path: "Sources/TerraMLX",
    ),
    .target(
      name: "TerraMetalProfiler",
      dependencies: [
        "TerraSystemProfiler",
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
      name: "CTerraANEBridge",
      path: "Sources/CTerraANEBridge",
      publicHeadersPath: "include",
      cSettings: [
        .define("APP_STORE", .when(configuration: .release)),
      ]
    ),
    .target(
      name: "TerraANEProfiler",
      dependencies: [
        "CTerraANEBridge",
        "TerraSystemProfiler",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
      ],
      path: "Sources/TerraANEProfiler",
      swiftSettings: [
        .define("APP_STORE", .when(configuration: .release)),
      ]
    ),
    .target(
      name: "TerraPowerProfiler",
      dependencies: [
        "TerraSystemProfiler",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
      ],
      path: "Sources/TerraPowerProfiler"
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
    ),
    .target(
      name: "TerraTracedMacro",
      dependencies: [
        "TerraTracedMacroPlugin",
        "TerraCore",
      ],
      path: "Sources/TerraTracedMacro",
    ),

    // MARK: - Test Targets

    .testTarget(
      name: "TerraANEProfilerTests",
      dependencies: [
        "TerraANEProfiler",
        "CTerraANEBridge",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
      ],
      path: "Tests/TerraANEProfilerTests"
    ),
    .testTarget(
      name: "TerraPowerProfilerTests",
      dependencies: [
        "TerraPowerProfiler",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
      ],
      path: "Tests/TerraPowerProfilerTests"
    ),
    .testTarget(
      name: "TerraSystemProfilerTests",
      dependencies: [
        "TerraSystemProfiler",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
      ],
      path: "Tests/TerraSystemProfilerTests"
    ),
    .testTarget(
      name: "TerraTests",
      dependencies: [
        "TerraCore",
        "TerraLlama",
        "TerraTraceKit",
        .product(name: "InMemoryExporter", package: "opentelemetry-swift"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "PersistenceExporter", package: "opentelemetry-swift"),
      ],
      path: "Tests/TerraTests",
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
    ),

    // MARK: - Examples

    .executableTarget(
      name: "TerraSample",
      dependencies: ["Terra"],
      path: "Examples/Terra Sample"
    )
  ]
)
