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
    .executable(name: "TerraSample", targets: ["TerraSample"]),
    .executable(name: "TraceMacApp", targets: ["TraceMacApp"]),
    .executable(name: "terra", targets: ["TerraCLI"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.25.0"),
    .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", .exact("2.3.0")),
    .package(url: "https://github.com/open-telemetry/opentelemetry-swift.git", .exact("2.3.0")),
    .package(url: "https://github.com/apple/swift-crypto.git", from: "4.2.0"),
    .package(url: "https://github.com/apple/swift-testing.git", from: "0.7.0")
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
        .product(name: "OpenTelemetryProtocolExporterHTTP", package: "opentelemetry-swift")
      ],
      path: "Sources/TerraTraceKit"
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
      name: "TerraTraceKitTests",
      dependencies: [
        "TerraTraceKit",
        .product(name: "OpenTelemetryProtocolExporterHTTP", package: "opentelemetry-swift"),
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
        .product(name: "Testing", package: "swift-testing")
      ],
      path: "Tests/TerraTraceKitTests"
    ),
    .testTarget(
      name: "TraceMacAppTests",
      dependencies: [
        "TraceMacApp",
        "TerraTraceKit",
        .product(name: "Testing", package: "swift-testing")
      ],
      path: "Tests/TraceMacAppTests"
    ),
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
