import Foundation
import XCTest

final class TelemetrySchemaValidatorTests: XCTestCase {
  func testValidatorAcceptsCurrentGoldenFixtures() throws {
    let root = try repoRoot()
    let result = try runValidator(root: root)

    XCTAssertEqual(result.status, 0, result.combinedOutput)
  }

  func testValidatorRejectsUnknownProtectedFixtureKeys() throws {
    let root = try repoRoot()
    let fixtureDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: fixtureDir) }

    let fixture = """
    {
      "schema_version": "terra.trace.golden.v1",
      "fixture_name": "unknown-key",
      "spans": [
        {
          "span_id": "0000000000000001",
          "name": "unknown-key",
          "attributes": {
            "terra.unregistered.fixture_key": {
              "type": "string",
              "value": "should-fail"
            }
          },
          "events": []
        }
      ]
    }
    """
    try fixture.write(
      to: fixtureDir.appendingPathComponent("unknown-key.json"),
      atomically: true,
      encoding: .utf8
    )

    let result = try runValidator(root: root, fixtureDir: fixtureDir)

    XCTAssertNotEqual(result.status, 0, result.combinedOutput)
    XCTAssertTrue(
      result.stderr.contains("unknown telemetry key 'terra.unregistered.fixture_key'"),
      result.combinedOutput
    )
  }
}

private struct ValidatorResult {
  let status: Int32
  let stdout: String
  let stderr: String

  var combinedOutput: String {
    [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
  }
}

private func runValidator(root: URL, fixtureDir: URL? = nil) throws -> ValidatorResult {
  let script = root.appendingPathComponent("Scripts/validate-telemetry-schema.py")
  let schema = root.appendingPathComponent("Docs/telemetry-schema.json")

  let outputPipe = Pipe()
  let errorPipe = Pipe()
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = ["python3", script.path, schema.path]
  if let fixtureDir {
    process.arguments?.append(contentsOf: ["--fixture-dir", fixtureDir.path])
  }
  process.standardOutput = outputPipe
  process.standardError = errorPipe

  try process.run()
  process.waitUntilExit()

  return ValidatorResult(
    status: process.terminationStatus,
    stdout: String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
    stderr: String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  )
}

private func repoRoot() throws -> URL {
  var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  let fileManager = FileManager.default

  while candidate.path != "/" {
    let script = candidate.appendingPathComponent("Scripts/validate-telemetry-schema.py")
    if fileManager.fileExists(atPath: script.path) {
      return candidate
    }
    candidate.deleteLastPathComponent()
  }

  throw NSError(
    domain: "TelemetrySchemaValidatorTests",
    code: 1,
    userInfo: [NSLocalizedDescriptionKey: "Could not locate repository root from \(#filePath)"]
  )
}
