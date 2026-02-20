import Foundation
import XCTest
@testable import TraceMacAppUI

final class TraceMacAppPerformanceGateTests: XCTestCase {
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

  func testTimelineCompactionAndRenderPrepOverheadGate() throws {
    try requirePerfGateEnabled()

    let samples = makeSamples(count: 12_000)
    let markerLimit = 1_000

    let result = measureOverhead(
      workload: "timeline_compaction_render_prep_path",
      sampleCount: 35,
      warmup: 6,
      sampleRepetitions: 8,
      baseline: {
        for _ in 0..<8 {
          _ = Self.manualCompactionStats(samples: samples, maxEventMarkers: markerLimit)
        }
      },
      instrumented: {
        for _ in 0..<8 {
          _ = TraceTimelineCanvasView.markerCompactionStats(samples: samples, maxEventMarkers: markerLimit)
        }
      }
    )

    try persist(results: [result], suite: "tracemacapp")

    XCTAssertLessThanOrEqual(result.p50Overhead, result.thresholdP50, "TraceMacApp p50 overhead exceeded gate")
    XCTAssertLessThanOrEqual(result.p95Overhead, result.thresholdP95, "TraceMacApp p95 overhead exceeded gate")
  }

  func testOutputDirectoryFallbackUsesRepoRelativeArtifactsPath() {
    let directory = outputDirectoryURL(environment: [:], filePath: #filePath)
    XCTAssertTrue(directory.path.hasSuffix("/Artifacts/rc-hardening/latest"))
  }

  private func makeSamples(count: Int) -> [TimelineMarkerDebugSample] {
    let kinds = ["decode", "promptEval", "tokenLifecycle", "recommendation", "anomaly", "stall"]
    var samples: [TimelineMarkerDebugSample] = []
    samples.reserveCapacity(count)

    for index in 0..<count {
      let x = CGFloat(index % 4_000) * 1.2
      let kind = kinds[index % kinds.count]
      let spanHex = String(format: "%016llx", UInt64(index % 2_048))
      samples.append(TimelineMarkerDebugSample(x: x, kind: kind, spanHex: spanHex))
    }

    return samples
  }

  private static func manualCompactionStats(
    samples: [TimelineMarkerDebugSample],
    maxEventMarkers: Int,
    bucketWidth: CGFloat = 2.0
  ) -> TimelineMarkerDebugStats {
    let resolvedLimit = max(1, maxEventMarkers)
    guard !samples.isEmpty else {
      return TimelineMarkerDebugStats(
        sourceCount: 0,
        keptCount: 0,
        coalescedCount: 0,
        sampledCount: 0,
        aggregationLevel: "none"
      )
    }

    let safeBucketWidth = max(0.01, bucketWidth)
    var seen: Set<String> = []
    var keys: [String] = []
    keys.reserveCapacity(samples.count)

    for sample in samples {
      let bucket = Int((sample.x / safeBucketWidth).rounded(.down))
      let key = "\(bucket)|\(sample.kind)|\(sample.spanHex)"
      if seen.insert(key).inserted {
        keys.append(key)
      }
    }

    let coalescedCount = max(0, samples.count - keys.count)
    if keys.count <= resolvedLimit {
      return TimelineMarkerDebugStats(
        sourceCount: samples.count,
        keptCount: keys.count,
        coalescedCount: coalescedCount,
        sampledCount: 0,
        aggregationLevel: coalescedCount > 0 ? "coalesced" : "none"
      )
    }

    let step = Int(ceil(Double(keys.count) / Double(resolvedLimit)))
    let kept = Array(stride(from: 0, to: keys.count, by: step)).count
    let sampledCount = max(0, keys.count - kept)

    return TimelineMarkerDebugStats(
      sourceCount: samples.count,
      keptCount: kept,
      coalescedCount: coalescedCount,
      sampledCount: sampledCount,
      aggregationLevel: "sampled"
    )
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

    var overheadRatios: [Double] = []
    overheadRatios.reserveCapacity(sampleCount)
    let measurementsPerSample = 5

    for index in 0..<sampleCount {
      var ratioPoint: [Double] = []
      ratioPoint.reserveCapacity(measurementsPerSample)

      for measurement in 0..<measurementsPerSample {
        let shouldMeasureBaselineFirst = (index + measurement).isMultiple(of: 2)
        let baselineDuration: Double
        let instrumentedDuration: Double

        if shouldMeasureBaselineFirst {
          baselineDuration = measureMS {
            for _ in 0..<sampleRepetitions {
              baseline()
            }
          } / Double(sampleRepetitions)

          instrumentedDuration = measureMS {
            for _ in 0..<sampleRepetitions {
              instrumented()
            }
          } / Double(sampleRepetitions)
        } else {
          instrumentedDuration = measureMS {
            for _ in 0..<sampleRepetitions {
              instrumented()
            }
          } / Double(sampleRepetitions)

          baselineDuration = measureMS {
            for _ in 0..<sampleRepetitions {
              baseline()
            }
          } / Double(sampleRepetitions)
        }

        let stabilizedBase = max(baselineDuration, 0.001)
        ratioPoint.append((instrumentedDuration - stabilizedBase) / stabilizedBase)
      }

      overheadRatios.append(median(ratioPoint))
    }

    let p50 = percentile(overheadRatios, 0.50)
    let p95 = percentile(overheadRatios, 0.95)

    return GateResult(
      suite: "tracemacapp",
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

    var text = "[TraceMacApp RC Performance Gate]\n"
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

  private func median(_ values: [Double]) -> Double {
    percentile(values, 0.5)
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
