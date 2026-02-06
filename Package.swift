// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "Terra",
  platforms: [
    .macOS(.v12),
    .iOS(.v13),
    .tvOS(.v13),
    .watchOS(.v6),
    .visionOS(.v1)
  ],
  products: [
    .library(name: "Terra", targets: ["Terra"]),
    .library(name: "TerraCoreML", targets: ["TerraCoreML"]),
    .library(name: "TerraTraceKit", targets: ["TerraTraceKit"]),
    .executable(name: "TerraSample", targets: ["TerraSample"])
  ],
  dependencies: [
    .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.3.0"),
    .package(url: "https://github.com/open-telemetry/opentelemetry-swift.git", from: "2.3.0"),
    .package(url: "https://github.com/apple/swift-crypto.git", from: "4.2.0"),
    .package(url: "https://github.com/apple/swift-testing.git", from: "0.99.0"),
  ],
  targets: [
    .target(
      name: "Terra",
      dependencies: [
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
        "Terra",
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
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
    .testTarget(
      name: "TerraTests",
      dependencies: [
        "Terra",
        .product(name: "InMemoryExporter", package: "opentelemetry-swift"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core")
      ],
      path: "Tests/TerraTests"
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
    .executableTarget(
      name: "TerraSample",
      dependencies: ["Terra"],
      path: "Examples/Terra Sample"
    )
  ]
)
