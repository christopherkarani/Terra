#if canImport(CoreML)
import CoreML
import Foundation
import ObjectiveC
import OpenTelemetryApi
import OpenTelemetrySdk
import InMemoryExporter
import Testing
@testable import TerraCoreML
@testable import TerraCore

// MARK: - Keys Constants

@Suite("TerraCoreML top-level", .serialized)
struct TerraCoreMLTopLevelTests {
private final class CancellationProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false

  func markCancelled() {
    lock.lock()
    cancelled = true
    lock.unlock()
  }

  var wasCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }
}

@Test("Keys.runtime has expected value")
func keysRuntimeValue() {
  #expect(TerraCoreML.Keys.runtime == "terra.runtime")
}

@Test("Keys.computeUnits has expected value")
func keysComputeUnitsValue() {
  #expect(TerraCoreML.Keys.computeUnits == "terra.coreml.compute_units")
}

// MARK: - Compute Unit Label Mapping

@Test("attributes maps MLComputeUnits.all to 'all'")
func computeUnitsAll() {
  let attrs = TerraCoreML.attributes(computeUnits: .all)
  #expect(attrs[TerraCoreML.Keys.computeUnits] == .string("all"))
}

@Test("attributes maps MLComputeUnits.cpuOnly to 'cpu_only'")
func computeUnitsCPUOnly() {
  let attrs = TerraCoreML.attributes(computeUnits: .cpuOnly)
  #expect(attrs[TerraCoreML.Keys.computeUnits] == .string("cpu_only"))
}

@Test("attributes maps MLComputeUnits.cpuAndGPU to 'cpu_and_gpu'")
func computeUnitsCPUAndGPU() {
  let attrs = TerraCoreML.attributes(computeUnits: .cpuAndGPU)
  #expect(attrs[TerraCoreML.Keys.computeUnits] == .string("cpu_and_gpu"))
}

@Test("attributes maps MLComputeUnits.cpuAndNeuralEngine to 'cpu_and_ane'")
func computeUnitsCPUAndNeuralEngine() {
  let attrs = TerraCoreML.attributes(computeUnits: .cpuAndNeuralEngine)
  #expect(attrs[TerraCoreML.Keys.computeUnits] == .string("cpu_and_ane"))
}

// MARK: - attributes(computeUnits:) Structure

@Test("attributes(computeUnits:) returns both runtime and compute_units keys")
func attributesContainsBothKeys() {
  let attrs = TerraCoreML.attributes(computeUnits: .all)
  #expect(attrs[TerraCoreML.Keys.runtime] == .string("coreml"))
  #expect(attrs[TerraCoreML.Keys.computeUnits] == .string("all"))
  #expect(attrs.count == 2)
}

// MARK: - attributes(configuration:) Equivalence

@Test("attributes(configuration:) produces same result as attributes(computeUnits:)")
func configurationAttributesMatchComputeUnitsAttributes() {
  let config = MLModelConfiguration()
  config.computeUnits = .cpuAndGPU

  let fromConfig = TerraCoreML.attributes(configuration: config)
  let fromUnits = TerraCoreML.attributes(computeUnits: .cpuAndGPU)

  #expect(fromConfig == fromUnits)
}

// MARK: - CoreMLInstrumentation Name Sanitization

@Test("sanitizeModelName strips control characters")
func sanitizeModelNameStripsControlCharacters() {
  let sanitized = CoreMLInstrumentation.sanitizeModelName("model\u{0000}\u{0007}-v1")
  #expect(sanitized == "model-v1")
}

@Test("sanitizeModelName trims and bounds name length to 256")
func sanitizeModelNameBoundsLength() {
  let longName = String(repeating: "a", count: 300)
  let sanitized = CoreMLInstrumentation.sanitizeModelName("  \(longName)  ")
  #expect(sanitized?.count == 256)
}

@Test("CoreML attributes never include prompt or response content keys")
func coreMLAttributesExcludeContent() {
  let attrs = TerraCoreML.attributes(computeUnits: .all)
  #expect(attrs[Terra.Keys.Terra.promptLength] == nil)
  #expect(attrs[Terra.Keys.Terra.promptHMACSHA256] == nil)
  #expect(attrs[Terra.Keys.Terra.promptSHA256] == nil)
  #expect(attrs[Terra.Keys.Terra.safetySubjectLength] == nil)
  #expect(attrs[Terra.Keys.Terra.safetySubjectHMACSHA256] == nil)
  #expect(attrs[Terra.Keys.Terra.safetySubjectSHA256] == nil)
}

@Test("synchronous compute-plan capture times out instead of blocking forever")
func synchronousComputePlanCaptureTimesOut() {
  let previousCapture = CoreMLInstrumentation.computePlanSummaryCapture
  let previousTimeout = CoreMLInstrumentation.synchronousCaptureTimeoutNanoseconds
  defer {
    CoreMLInstrumentation.computePlanSummaryCapture = previousCapture
    CoreMLInstrumentation.synchronousCaptureTimeoutNanoseconds = previousTimeout
  }

  CoreMLInstrumentation.computePlanSummaryCapture = { _, _ in
    try? await Task.sleep(nanoseconds: 200_000_000)
    return TerraCoreMLComputePlanSummary(
      captureStatus: .captured,
      modelStructure: "program",
      estimatedPrimaryDevice: "ane",
      supportedDevices: ["ane"],
      nodeCount: 1,
      captureDurationMS: 200,
      operationEstimates: [],
      errorType: nil,
      probeStatus: TerraCoreMLComputePlanSummary.CaptureStatus.captured.rawValue,
      probeSource: "test"
    )
  }
  CoreMLInstrumentation.synchronousCaptureTimeoutNanoseconds = 10_000_000

  let summary = CoreMLInstrumentation.captureSummarySynchronously(
    contentsOf: URL(fileURLWithPath: "/tmp/model.mlmodelc"),
    configuration: MLModelConfiguration()
  )

  #expect(summary.captureStatus == .loadFailed)
  #expect(summary.errorType == "terra.coreml.compute_plan.capture_timeout")
  #expect(summary.probeSource == "mlcomputeplan")
}

@Test("synchronous compute-plan capture cancels underlying task on timeout")
func synchronousComputePlanCaptureCancelsUnderlyingTaskOnTimeout() async throws {
  let previousCapture = CoreMLInstrumentation.computePlanSummaryCapture
  let previousTimeout = CoreMLInstrumentation.synchronousCaptureTimeoutNanoseconds
  defer {
    CoreMLInstrumentation.computePlanSummaryCapture = previousCapture
    CoreMLInstrumentation.synchronousCaptureTimeoutNanoseconds = previousTimeout
  }

  let probe = CancellationProbe()
  CoreMLInstrumentation.computePlanSummaryCapture = { _, _ in
    while !Task.isCancelled {
      try? await Task.sleep(nanoseconds: 5_000_000)
    }
    probe.markCancelled()
    return TerraCoreMLComputePlanSummary(
      captureStatus: .captured,
      modelStructure: "program",
      estimatedPrimaryDevice: "ane",
      supportedDevices: ["ane"],
      nodeCount: 1,
      captureDurationMS: 200,
      operationEstimates: [],
      errorType: nil,
      probeStatus: TerraCoreMLComputePlanSummary.CaptureStatus.captured.rawValue,
      probeSource: "test"
    )
  }
  CoreMLInstrumentation.synchronousCaptureTimeoutNanoseconds = 5_000_000

  _ = CoreMLInstrumentation.captureSummarySynchronously(
    contentsOf: URL(fileURLWithPath: "/tmp/model.mlmodelc"),
    configuration: MLModelConfiguration()
  )
  for _ in 0..<100 where !probe.wasCancelled {
    try await Task.sleep(nanoseconds: 10_000_000)
  }

  #expect(probe.wasCancelled)
}

// MARK: - P0-6 Batch prediction swizzling

@Test("Batch prediction selectors are recognized on MLModel class")
func batchPredictionSelectorsExistOnMLModelClass() {
  // Sanity: the swizzle code looks up these selectors via class_getInstanceMethod.
  // If Apple ever renames or removes them we want the test suite to fail fast.
  let cls: AnyClass = NSClassFromString("MLModel")!
  let batchNoOptions = NSSelectorFromString("predictionsFromBatch:error:")
  let batchWithOptions = NSSelectorFromString("predictionsFromBatch:options:error:")

  #expect(class_getInstanceMethod(cls, batchNoOptions) != nil)
  #expect(class_getInstanceMethod(cls, batchWithOptions) != nil)
}

@Test("Batch prediction key has expected schema name")
func batchPredictionKeyHasExpectedName() {
  // Locks in the wire format documented in Docs/telemetry-schema.json.
  #expect(CoreMLInstrumentation.predictionBatchCountAttributeKey == "terra.coreml.prediction.batch_count")
}

@Test("testBatchPredictionsSelectorIsSwizzledAndSpanIsEmitted")
func testBatchPredictionsSelectorIsSwizzledAndSpanIsEmitted() {
  let previousTracer = OpenTelemetry.instance.tracerProvider
  let exporter = InMemoryExporter()
  let provider = TracerProviderSdk()
  provider.addSpanProcessor(SimpleSpanProcessor(spanExporter: exporter))
  OpenTelemetry.registerTracerProvider(tracerProvider: provider)
  defer {
    OpenTelemetry.registerTracerProvider(tracerProvider: previousTracer)
  }

  // Drive the same code path the swizzle uses for batch predictions, without
  // requiring a real `.mlmodelc` fixture in the repository. This exercises
  // span name, attribute set, and the new batch_count attribute.
  CoreMLInstrumentation._emitBatchPredictionSpanForTesting(
    modelName: "test_batch_model",
    computeUnitsLabel: "all",
    durationMs: 12.5,
    batchCount: 8,
    error: nil
  )

  provider.forceFlush()
  let spans = exporter.getFinishedSpanItems()
  let span = try! #require(
    spans.first(where: {
      $0.name == "gen_ai.inference"
        && $0.attributes[Terra.Keys.GenAI.requestModel]?.description == "test_batch_model"
    })
  )
  #expect(span.attributes[CoreMLInstrumentation.predictionBatchCountAttributeKey]?.description == "8")
  #expect(span.attributes[Terra.Keys.Terra.runtime]?.description == "coreml")
  #expect(span.attributes[Terra.Keys.Terra.autoInstrumented]?.description == "true")
  #expect(span.attributes[TerraCoreML.Keys.computeUnits]?.description == "all")
  #expect(span.attributes["terra.coreml.prediction.duration_ms"]?.description == "12.5")
  #expect(span.status == .ok || span.status == .unset)
}

@Test("testBatchPredictionsErrorPathRecordsSpanWithStatus")
func testBatchPredictionsErrorPathRecordsSpanWithStatus() {
  let previousTracer = OpenTelemetry.instance.tracerProvider
  let exporter = InMemoryExporter()
  let provider = TracerProviderSdk()
  provider.addSpanProcessor(SimpleSpanProcessor(spanExporter: exporter))
  OpenTelemetry.registerTracerProvider(tracerProvider: provider)
  defer {
    OpenTelemetry.registerTracerProvider(tracerProvider: previousTracer)
  }

  let nsError = NSError(
    domain: "com.example.batch",
    code: 99,
    userInfo: [NSLocalizedDescriptionKey: "batch failed at item 3"]
  )

  CoreMLInstrumentation._emitBatchPredictionSpanForTesting(
    modelName: "errored_batch_model",
    computeUnitsLabel: "cpu_only",
    durationMs: 5.0,
    batchCount: 16,
    error: nsError
  )

  provider.forceFlush()
  let spans = exporter.getFinishedSpanItems()
  let span = try! #require(
    spans.first(where: {
      $0.name == "gen_ai.inference"
        && $0.attributes[Terra.Keys.GenAI.requestModel]?.description == "errored_batch_model"
    })
  )
  #expect(span.attributes[CoreMLInstrumentation.predictionBatchCountAttributeKey]?.description == "16")
  if case let .error(description) = span.status {
    #expect(description == "com.example.batch(code:99)")
    #expect(description.contains("/Users") == false)
    #expect(description.contains("item 3") == false)
  } else {
    Issue.record("Expected error status, got \(span.status)")
  }
}
}
#endif
