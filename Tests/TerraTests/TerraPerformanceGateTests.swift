import Foundation
import XCTest
@testable import TerraCore

final class TerraPerformanceGateTests: XCTestCase {
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

  func testTerraInstrumentationOverheadGate() async throws {
    try requirePerfGateEnabled()

    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let inference = await measureOverhead(
      workload: "inference_span_path",
      sampleCount: 32,
      warmup: 6,
      sampleRepetitions: 8,
      baseline: {
        _ = self.syntheticWork(seed: 17, rounds: 50_000)
      },
      instrumented: { iteration in
        let request = Terra.InferenceRequest(
          model: "perf/model",
          runtime: .coreML,
          requestID: "perf-inference-\(iteration)"
        )
        await Terra.withInferenceSpan(request) { _ in
          _ = self.syntheticWork(seed: 17, rounds: 50_000)
        }
      }
    )

    let streaming = await measureOverhead(
      workload: "streaming_span_path",
      sampleCount: 24,
      warmup: 5,
      sampleRepetitions: 8,
      baseline: {
        _ = self.syntheticWork(seed: 29, rounds: 60_000)
      },
      instrumented: { iteration in
        let request = Terra.InferenceRequest(
          model: "perf/model",
          runtime: .coreML,
          requestID: "perf-stream-\(iteration)",
          stream: true
        )
        await Terra.withStreamingInferenceSpan(request) { stream in
          _ = self.syntheticWork(seed: 29, rounds: 60_000)
          for _ in 0..<24 {
            stream.recordChunk()
            stream.recordToken()
          }
        }
      }
    )

    let results = [inference, streaming]
    try persist(results: results, suite: "terra")

    for result in results {
      XCTAssertLessThanOrEqual(
        result.p50Overhead,
        result.thresholdP50,
        "\(result.workload) p50 overhead exceeded gate"
      )
      XCTAssertLessThanOrEqual(
        result.p95Overhead,
        result.thresholdP95,
        "\(result.workload) p95 overhead exceeded gate"
      )
    }
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
    baseline: @escaping () -> Void,
    instrumented: @escaping (_ iteration: Int) async -> Void
  ) async -> GateResult {
    for _ in 0..<warmup {
      baseline()
      await instrumented(-1)
    }

    var baselineMS: [Double] = []
    var instrumentedMS: [Double] = []
    baselineMS.reserveCapacity(sampleCount)
    instrumentedMS.reserveCapacity(sampleCount)

    for index in 0..<sampleCount {
      let baselineDuration = measureMS {
        for _ in 0..<sampleRepetitions {
          baseline()
        }
      } / Double(sampleRepetitions)
      baselineMS.append(max(0, baselineDuration))

      let instrumentedDuration = await measureAsyncMS {
        for repetition in 0..<sampleRepetitions {
          await instrumented((index * sampleRepetitions) + repetition)
        }
      } / Double(sampleRepetitions)
      instrumentedMS.append(max(0, instrumentedDuration))
    }

    let overheadRatios = zip(baselineMS, instrumentedMS).map { base, instrumented in
      let stabilizedBase = max(base, 0.001)
      return (instrumented - stabilizedBase) / stabilizedBase
    }

    let p50 = percentile(overheadRatios, 0.50)
    let p95 = percentile(overheadRatios, 0.95)

    return GateResult(
      suite: "terra",
      workload: workload,
      sampleCount: sampleCount,
      p50Overhead: p50,
      p95Overhead: p95,
      thresholdP50: 0.03,
      thresholdP95: 0.07,
      passed: p50 <= 0.03 && p95 <= 0.07
    )
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

    var text = "[Terra RC Performance Gate]\n"
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
    return durationToMilliseconds(duration)
  }

  private func measureAsyncMS(_ block: () async -> Void) async -> Double {
    let clock = ContinuousClock()
    let start = clock.now
    await block()
    return durationToMilliseconds(start.duration(to: clock.now))
  }

  private func durationToMilliseconds(_ duration: Duration) -> Double {
    let secondsMS = Double(duration.components.seconds) * 1000
    let attosecondsMS = Double(duration.components.attoseconds) / 1_000_000_000_000_000
    return max(0, secondsMS + attosecondsMS)
  }

  private func syntheticWork(seed: Int, rounds: Int) -> Int {
    var accumulator = seed
    for index in 0..<rounds {
      accumulator = (accumulator &* 1103515245 &+ 12345 &+ index) & 0x7fffffff
      accumulator ^= (accumulator >> 7)
    }
    return accumulator
  }
}
