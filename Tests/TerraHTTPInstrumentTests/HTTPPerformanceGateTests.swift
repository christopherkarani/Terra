import Foundation
import XCTest
@testable import TerraHTTPInstrument

final class HTTPPerformanceGateTests: XCTestCase {
  private struct GateResult: Codable {
    let suite: String
    let workload: String
    let sampleCount: Int
    let p50Overhead: Double
    let p95Overhead: Double
    let thresholdP50: Double
    let thresholdP95: Double
    let passed: Bool
  }

  func testHTTPStreamParserOverheadGate() throws {
    try requirePerfGateEnabled()

    let payload = makeRepresentativeNDJSONPayload(chunks: 200)
    let result = measureOverhead(
      workload: "http_stream_parser_path",
      sampleCount: 40,
      warmup: 8,
      sampleRepetitions: 12,
      baseline: {
        for _ in 0..<16 {
          _ = AIResponseStreamParser.parse(data: payload, runtime: .unknown, requestModel: "qwen2")
        }
      },
      instrumented: {
        for _ in 0..<16 {
          _ = AIResponseStreamParser.parse(data: payload, runtime: .ollama, requestModel: "qwen2")
        }
      }
    )

    try persist(results: [result], suite: "http")

    XCTAssertLessThanOrEqual(result.p50Overhead, result.thresholdP50, "HTTP parser p50 overhead exceeded gate")
    XCTAssertLessThanOrEqual(result.p95Overhead, result.thresholdP95, "HTTP parser p95 overhead exceeded gate")
  }

  func testOutputDirectoryFallbackUsesRepoRelativeArtifactsPath() {
    let directory = outputDirectoryURL(environment: [:], filePath: #filePath)
    XCTAssertTrue(directory.path.hasSuffix("/Artifacts/rc-hardening/latest"))
  }

  private func measureOverhead(
    workload: String,
    sampleCount: Int,
    warmup: Int,
    sampleRepetitions: Int,
    baseline: () -> Void,
    instrumented: () -> Void
  ) -> GateResult {
    for _ in 0..<warmup {
      baseline()
      instrumented()
    }

    var baselineMS: [Double] = []
    var instrumentedMS: [Double] = []
    baselineMS.reserveCapacity(sampleCount)
    instrumentedMS.reserveCapacity(sampleCount)

    for _ in 0..<sampleCount {
      let baselineDuration = measureMS {
        for _ in 0..<sampleRepetitions {
          baseline()
        }
      } / Double(sampleRepetitions)
      baselineMS.append(baselineDuration)

      let instrumentedDuration = measureMS {
        for _ in 0..<sampleRepetitions {
          instrumented()
        }
      } / Double(sampleRepetitions)
      instrumentedMS.append(instrumentedDuration)
    }

    let overheadRatios = zip(baselineMS, instrumentedMS).map { base, instrumented in
      let stabilizedBase = max(base, 0.001)
      return (instrumented - stabilizedBase) / stabilizedBase
    }

    let p50 = percentile(overheadRatios, 0.50)
    let p95 = percentile(overheadRatios, 0.95)

    return GateResult(
      suite: "http",
      workload: workload,
      sampleCount: sampleCount,
      p50Overhead: p50,
      p95Overhead: p95,
      thresholdP50: 0.03,
      thresholdP95: 0.07,
      passed: p50 <= 0.03 && p95 <= 0.07
    )
  }

  private func makeRepresentativeNDJSONPayload(chunks: Int) -> Data {
    var lines: [String] = []
    lines.reserveCapacity(chunks + 1)
    for index in 0..<chunks {
      lines.append(
        #"{"model":"qwen2","created_at":"2024-01-01T00:00:"#
          + String(format: "%02d", index % 60)
          + #".000Z","response":"token","done":false}"#
      )
    }
    lines.append(
      #"{"model":"qwen2","created_at":"2024-01-01T00:00:59.500Z","done":true,"prompt_eval_count":256,"eval_count":200,"prompt_eval_duration":1200000000,"eval_duration":2800000000,"load_duration":900000}"#
    )

    return Data(lines.joined(separator: "\n").utf8)
  }

  private func persist(results: [GateResult], suite: String) throws {
    let directory = outputDirectoryURL()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let jsonURL = directory.appendingPathComponent("\(suite)-performance-gate.json")
    let textURL = directory.appendingPathComponent("\(suite)-performance-gate.txt")

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let jsonData = try encoder.encode(results)
    try jsonData.write(to: jsonURL, options: [.atomic])

    var text = "[HTTP RC Performance Gate]\n"
    for result in results {
      let p50Percent = String(format: "%.3f%%", result.p50Overhead * 100)
      let p95Percent = String(format: "%.3f%%", result.p95Overhead * 100)
      text += "- \(result.workload): p50=\(p50Percent) p95=\(p95Percent) threshold=(3.000%,7.000%) pass=\(result.passed)\n"
    }
    try Data(text.utf8).write(to: textURL, options: [.atomic])
  }

  private func requirePerfGateEnabled() throws {
    let value = ProcessInfo.processInfo.environment["TERRA_ENABLE_PERF_GATES"] ?? "0"
    if !isTruthy(value) {
      throw XCTSkip("Skipping performance gate tests: set TERRA_ENABLE_PERF_GATES=1")
    }
  }

  private func outputDirectoryURL(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    filePath: String = #filePath
  ) -> URL {
    if let raw = environment["TERRA_RC_OUTPUT_DIR"], !raw.isEmpty {
      return URL(fileURLWithPath: raw, isDirectory: true)
    }
    return repositoryRootURL(filePath: filePath)
      .appendingPathComponent("Artifacts/rc-hardening/latest", isDirectory: true)
  }

  private func repositoryRootURL(filePath: String = #filePath) -> URL {
    var url = URL(fileURLWithPath: filePath)
    while url.path != "/", url.lastPathComponent != "Tests" {
      url.deleteLastPathComponent()
    }
    if url.lastPathComponent == "Tests" {
      return url.deletingLastPathComponent()
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
  }

  private func isTruthy(_ value: String) -> Bool {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "1", "true", "yes", "on":
      return true
    default:
      return false
    }
  }

  private func percentile(_ values: [Double], _ p: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let clampedP = max(0, min(p, 1))
    let position = clampedP * Double(sorted.count - 1)
    let lower = Int(position.rounded(.down))
    let upper = Int(position.rounded(.up))
    if lower == upper {
      return sorted[lower]
    }
    let fraction = position - Double(lower)
    return sorted[lower] + ((sorted[upper] - sorted[lower]) * fraction)
  }

  private func measureMS(_ block: () -> Void) -> Double {
    let clock = ContinuousClock()
    let duration = clock.measure {
      block()
    }
    let secondsMS = Double(duration.components.seconds) * 1000
    let attosecondsMS = Double(duration.components.attoseconds) / 1_000_000_000_000_000
    return max(0, secondsMS + attosecondsMS)
  }
}
