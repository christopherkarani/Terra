// TerraSDKBenchmarks — minimal microbenchmark for Terra hot paths.
//
// Measures cold-start lifecycle, the workflow root span hot path, and the
// manual `Terra.startSpan(name:)` hot path. Outputs P50/P95/P99 latency
// histograms (in microseconds) to stdout and exits.
//
// Designed to run in well under 30 seconds on a 2024 Apple Silicon Mac.

import Foundation
import Terra

// MARK: - Configuration

private let workflowIterations = 10_000
private let manualSpanIterations = 10_000

// MARK: - Timing primitives

private struct LatencySample {
  let nanoseconds: UInt64
}

private func nanoseconds(_ duration: Duration) -> UInt64 {
  let comps = duration.components
  let secNanos = UInt64(Swift.max(comps.seconds, 0)) &* 1_000_000_000
  let attoNanos = UInt64(Swift.max(comps.attoseconds, 0) / 1_000_000_000)
  return secNanos &+ attoNanos
}

private func formatNs(_ ns: UInt64) -> String {
  let micros = Double(ns) / 1_000.0
  return String(format: "%.2f us", micros)
}

private struct Histogram {
  let label: String
  let count: Int
  let p50: UInt64
  let p95: UInt64
  let p99: UInt64
  let minValue: UInt64
  let maxValue: UInt64
  let mean: UInt64

  init(label: String, samples: [LatencySample]) {
    precondition(!samples.isEmpty, "histogram requires at least one sample")
    let sorted = samples.map(\.nanoseconds).sorted()
    self.label = label
    self.count = sorted.count
    self.minValue = sorted.first!
    self.maxValue = sorted.last!
    let sum = sorted.reduce(UInt64(0), &+)
    self.mean = sum / UInt64(sorted.count)
    self.p50 = Histogram.percentile(sorted, 0.50)
    self.p95 = Histogram.percentile(sorted, 0.95)
    self.p99 = Histogram.percentile(sorted, 0.99)
  }

  private static func percentile(_ sorted: [UInt64], _ p: Double) -> UInt64 {
    let raw = Int((p * Double(sorted.count - 1)).rounded())
    let clamped = Swift.min(Swift.max(raw, 0), sorted.count - 1)
    return sorted[clamped]
  }

  func report() {
    print(
      """
      \(label) [n=\(count)]
        min  \(formatNs(minValue))
        p50  \(formatNs(p50))
        p95  \(formatNs(p95))
        p99  \(formatNs(p99))
        max  \(formatNs(maxValue))
        mean \(formatNs(mean))
      """
    )
  }
}

// MARK: - Benchmarks

private func benchmarkLifecycleColdStart() async throws -> LatencySample {
  let clock = ContinuousClock()
  let elapsed = try await clock.measure {
    try await Terra.start(.init(preset: .quickstart))
    await Terra.shutdown()
  }
  return LatencySample(nanoseconds: nanoseconds(elapsed))
}

private func benchmarkWorkflowHotPath(iterations: Int) async throws -> [LatencySample] {
  try await Terra.start(.init(preset: .quickstart))

  // Warmup so first-call overhead doesn't dominate the histogram.
  for _ in 0..<100 {
    _ = try await Terra.workflow(name: "bench.warmup") { _ in 0 }
  }

  let clock = ContinuousClock()
  var samples = [LatencySample]()
  samples.reserveCapacity(iterations)

  for index in 0..<iterations {
    let elapsed = try await clock.measure {
      _ = try await Terra.workflow(name: "bench.workflow", id: "bench-\(index)") { _ in
        0
      }
    }
    samples.append(LatencySample(nanoseconds: nanoseconds(elapsed)))
  }

  await Terra.shutdown()
  return samples
}

private func benchmarkStartSpanHotPath(iterations: Int) async throws -> [LatencySample] {
  try await Terra.start(.init(preset: .quickstart))

  for _ in 0..<100 {
    let span = Terra.startSpan(name: "bench.warmup")
    span.end()
  }

  let clock = ContinuousClock()
  var samples = [LatencySample]()
  samples.reserveCapacity(iterations)

  for _ in 0..<iterations {
    let elapsed = clock.measure {
      let span = Terra.startSpan(name: "bench.startSpan")
      span.end()
    }
    samples.append(LatencySample(nanoseconds: nanoseconds(elapsed)))
  }

  await Terra.shutdown()
  return samples
}

// MARK: - Entry point

private func silenceStderr() {
  // The OTLP exporter prints connection failures to stderr when the local
  // dashboard endpoint is unreachable. Those messages are not the
  // measurement we care about; redirect stderr to /dev/null so the
  // histogram report stays the only visible output.
  let fd = open("/dev/null", O_WRONLY)
  if fd >= 0 {
    dup2(fd, fileno(stderr))
    close(fd)
  }
}

silenceStderr()

private func runAll() async throws {
  print("Terra SDK Microbenchmarks")
  print("=========================")
  print("Iterations: workflow=\(workflowIterations), startSpan=\(manualSpanIterations)")
  print("")

  let coldStart = try await benchmarkLifecycleColdStart()
  print("cold-start lifecycle (start + shutdown)")
  print("  one-shot \(formatNs(coldStart.nanoseconds))")
  print("")

  let workflowSamples = try await benchmarkWorkflowHotPath(iterations: workflowIterations)
  Histogram(label: "Terra.workflow(name:_:) hot path", samples: workflowSamples).report()
  print("")

  let startSpanSamples = try await benchmarkStartSpanHotPath(iterations: manualSpanIterations)
  Histogram(label: "Terra.startSpan(name:) + end() hot path", samples: startSpanSamples).report()
  print("")

  print("Done.")
}

try await runAll()

// Terminate immediately so the OTLP exporter's internal retry queue does not
// extend wall-clock time past the histograms we just printed. Span lifecycle
// hot-path numbers above are unaffected by exporter drain time.
exit(0)
