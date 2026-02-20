import XCTest

final class TerraV1FixtureTests: XCTestCase {
  private let requiredContractAttributes: Set<String> = [
    "terra.semantic.version",
    "terra.schema.family",
    "terra.runtime",
    "terra.request.id",
    "terra.session.id",
    "terra.model.fingerprint",
  ]

  private let allowedRuntimes: Set<String> = [
    "coreml",
    "foundation_models",
    "mlx",
    "ollama",
    "lm_studio",
    "llama_cpp",
    "openclaw_gateway",
    "http_api",
  ]

  private let canonicalSchemaPathParts = ["Docs", "TelemetryConvention", "terra-v1.schema.json"]
  private let canonicalRuntimeRoots = Set([
    "terra.model.load",
    "terra.inference",
    "terra.stage.prompt_eval",
    "terra.stage.decode",
    "terra.stream.lifecycle",
  ])

  func testTerraV1SchemaIsLoadableAndWellFormed() throws {
    let schemaURL = projectRoot()
      .appendingPathComponent(canonicalSchemaPathParts.joined(separator: "/"))
    let data = try Data(contentsOf: schemaURL)
    let decoded = try JSONSerialization.jsonObject(with: data, options: [])
    guard let schema = decoded as? [String: Any] else {
      XCTFail("Expected schema JSON object")
      return
    }

    XCTAssertEqual(schema["title"] as? String, "Terra v1 Telemetry Convention")
    XCTAssertEqual(schema["version"] as? String, "v1")

    let schemaDefinitions = schema["properties"] as? [String: Any] ?? schema

    guard let required = schemaDefinitions["required_attributes"] as? [String: Any] else {
      XCTFail("Expected required_attributes object")
      return
    }

    let requiredAttributeKeys: [String]
    if let requiredList = required["required"] as? [String] {
      requiredAttributeKeys = requiredList
    } else {
      requiredAttributeKeys = [
        "terra.semantic.version",
        "terra.schema.family",
        "terra.runtime",
      ]
    }
    XCTAssertTrue(requiredAttributeKeys.contains("terra.semantic.version"))
    XCTAssertTrue(requiredAttributeKeys.contains("terra.schema.family"))
    XCTAssertTrue(requiredAttributeKeys.contains("terra.runtime"))

    if let properties = required["properties"] as? [String: Any] {
      XCTAssertNotNil(properties["terra.semantic.version"])
      XCTAssertNotNil(properties["terra.schema.family"])
      XCTAssertNotNil(properties["terra.runtime"])
    } else {
      XCTAssertNotNil(required["terra.semantic.version"])
      XCTAssertNotNil(required["terra.schema.family"])
      XCTAssertNotNil(required["terra.runtime"])
    }

    guard let spanNamesProperty = schemaDefinitions["span_names"] as? [String: Any] else {
      XCTFail("Expected span_names object")
      return
    }
    let spanNameValuesContainer: [String: Any]
    if let properties = spanNamesProperty["properties"] as? [String: Any] {
      spanNameValuesContainer = properties
    } else {
      spanNameValuesContainer = spanNamesProperty
    }
    let spanNameValues = Set(spanNameValuesContainer.values.compactMap { value in
      if let stringValue = value as? String {
        return stringValue
      }
      if let object = value as? [String: Any], let constValue = object["const"] as? String {
        return constValue
      }
      return nil
    })
    for span in canonicalSchemaPathRoots() {
      XCTAssertTrue(
        spanNameValues.contains(span),
        "Missing span name value in schema: \(span)"
      )
    }
    if let legacySpanNames = schema[ "span_names"] as? [String: Any] {
      for span in canonicalSchemaPathRoots() {
        XCTAssertNotNil(
          legacySpanNames[span],
          "Missing span name key in schema: \(span)"
        )
      }
    }
  }

  func testTerraV1FixturesDirectoryIsComplete() throws {
    let files = try fixtureFiles()
    XCTAssertFalse(files.isEmpty)

    var seenRuntimes = Set<String>()
    for file in files {
      let fixture = try loadFixture(file: file)
      guard let runtime = fixture["runtime"] as? String else {
        XCTFail("Missing runtime in \(file.lastPathComponent)")
        continue
      }
      XCTAssertTrue(allowedRuntimes.contains(runtime), "Unknown runtime \(runtime)")
      seenRuntimes.insert(runtime)

      guard let schemaVersion = fixture["schema_version"] as? String else {
        XCTFail("Missing schema_version in \(file.lastPathComponent)")
        continue
      }
      XCTAssertEqual(schemaVersion, "v1", "Fixture schema_version mismatch: \(file.lastPathComponent)")

      guard let contract = fixture["contract"] as? [String: Any] else {
        XCTFail("Missing contract in \(file.lastPathComponent)")
        continue
      }

      for key in requiredContractAttributes {
        XCTAssertNotNil(contract[key], "Missing \(key) in \(file.lastPathComponent)")
      }
      if runtime != "openclaw_gateway" {
        XCTAssertEqual(contract["terra.runtime"] as? String, runtime)
      }
      XCTAssertEqual((contract["terra.semantic.version"] as? String) ?? "", "v1")
      XCTAssertEqual((contract["terra.schema.family"] as? String) ?? "", "terra")

      guard let spans = fixture["spans"] as? [[String: Any]], !spans.isEmpty else {
        XCTFail("No spans in \(file.lastPathComponent)")
        continue
      }

      XCTAssertTrue(
        spans.contains(where: { span in
          guard let name = span["name"] as? String else { return false }
          return canonicalSchemaPathRoots().contains(name)
        }),
        "Missing canonical root span in \(file.lastPathComponent)"
      )

      if let traits = fixture["runtime_traits"] as? [String] {
        XCTAssertFalse(traits.isEmpty)
      }
    }

    let expected = Set([
      "coreml",
      "foundation_models",
      "mlx",
      "ollama",
      "lm_studio",
      "llama_cpp",
      "openclaw_gateway",
      "http_api",
    ])
    XCTAssertEqual(seenRuntimes.intersection(expected), expected, "Missing fixtures for required runtimes")
  }

  func testRuntimeSpecificSemanticsFromFixtures() throws {
    let files = try fixtureFiles()

    for file in files {
      let fixture = try loadFixture(file: file)
      guard
        let runtime = fixture["runtime"] as? String,
        let spans = fixture["spans"] as? [[String: Any]]
      else {
        continue
      }

      let events = spans.flatMap { span in
        span["events"] as? [[String: Any]] ?? []
      }

      XCTAssertFalse(events.isEmpty, "No stream events in \(file.lastPathComponent)")
      XCTAssertTrue(
        events.contains { $0["name"] as? String == "terra.stream.lifecycle" },
        "Missing stream lifecycle event in \(file.lastPathComponent)"
      )

      if runtime == "openclaw_gateway" {
        let contract = fixture["contract"] as? [String: Any]
        XCTAssertEqual(contract?["terra.openclaw.gateway"] as? String, "true")
        XCTAssertNotNil(contract?["terra.openclaw.mode"] as? String)
        XCTAssertTrue(
          events.contains { event in
            event.keys.contains("terra.openclaw.gateway")
              || (event["name"] as? String)?.contains("openclaw") == true
          },
          "OpenClaw runtime fixture missing openclaw signal in \(file.lastPathComponent)"
        )
      }

      if runtime == "lm_studio" {
        XCTAssertTrue(
          events.contains { event in
            (event["name"] as? String)?.contains("prompt") == true
              || (event["name"] as? String)?.contains("decode") == true
          },
          "LM Studio fixture missing prompt/decode events in \(file.lastPathComponent)"
        )
      }

      if runtime == "ollama" {
        XCTAssertTrue(
          events.contains { $0["name"] as? String == "terra.stage.prompt_eval" },
          "Ollama fixture missing prompt_eval stage in \(file.lastPathComponent)"
        )
      }

      if runtime == "coreml" {
        XCTAssertTrue(
          events.contains { event in
            (event["name"] as? String)?.contains("stage.decode") == true
          },
          "CoreML fixture missing decode stage in \(file.lastPathComponent)"
        )
      }

      if runtime == "foundation_models" {
        XCTAssertTrue(
          events.contains { event in
            (event["name"] as? String) == "terra.stage.decode"
              || (event["name"] as? String) == "terra.stage.prompt_eval"
          },
          "Foundation Models fixture missing stage events in \(file.lastPathComponent)"
        )
      }
    }
  }

  private func fixtureFiles() throws -> [URL] {
    let url = fixtureDirectory()
    let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    return urls.filter { $0.pathExtension.lowercased() == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
  }

  private func fixtureDirectory() -> URL {
    return projectRoot()
      .appendingPathComponent("Tests/TerraTraceKitTests/Fixtures/TerraV1")
  }

  private func loadFixture(file: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: file)
    let decoded = try JSONSerialization.jsonObject(with: data, options: [])
    guard let dictionary = decoded as? [String: Any] else {
      throw NSError(domain: "TerraV1FixtureTests", code: 1)
    }
    return dictionary
  }

  private func projectRoot() -> URL {
    // Start from .../Tests/TerraTraceKitTests/TerraV1FixtureTests.swift
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while root.lastPathComponent != "Tests" {
      root = root.deletingLastPathComponent()
    }
    return root.deletingLastPathComponent()
  }

  private func canonicalSchemaPathRoots() -> Set<String> {
    return canonicalRuntimeRoots
  }
}
