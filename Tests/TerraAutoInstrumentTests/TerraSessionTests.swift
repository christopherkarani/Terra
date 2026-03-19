import Foundation
import InMemoryExporter
import OpenTelemetryApi
import OpenTelemetrySdk
import Testing

#if canImport(CoreML)
import CoreML
@testable import TerraCoreML
#endif

@testable import Terra
@testable import TerraCore
@testable import TerraTraceKit

private struct SessionSpanHarness {
  let previousTracerProvider: any TracerProvider
  let spanExporter: InMemoryExporter
  let tracerProvider: TracerProviderSdk

  init() {
    previousTracerProvider = OpenTelemetry.instance.tracerProvider
    Terra.resetOpenTelemetryForTesting()
    spanExporter = InMemoryExporter()
    tracerProvider = TracerProviderSdk()
    tracerProvider.addSpanProcessor(SimpleSpanProcessor(spanExporter: spanExporter))
    OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
    Terra.install(.init(tracerProvider: tracerProvider, registerProvidersAsGlobal: false))
  }

  func finishedSpans() -> [SpanData] {
    tracerProvider.forceFlush()
    return spanExporter.getFinishedSpanItems()
  }

  func tearDown() {
    Terra.resetOpenTelemetryForTesting()
    OpenTelemetry.registerTracerProvider(tracerProvider: previousTracerProvider)
  }
}

private struct MockDashboardDiscovery: TerraDashboardDiscovering {
  let endpoint: URL?

  func discoverEndpoint(timeout: Duration) async -> URL? {
    endpoint
  }
}

private final class TestSessionLogger: TerraSessionLogging, @unchecked Sendable {
  private let lock = NSLock()
  private(set) var warnings: [String] = []
  private(set) var errors: [String] = []

  func warning(_ message: String) {
    lock.lock()
    warnings.append(message)
    lock.unlock()
  }

  func error(_ message: String) {
    lock.lock()
    errors.append(message)
    lock.unlock()
  }
}

private enum InferenceFailure: Error {
  case failed
}

#if canImport(CoreML)
private func unsupportedComputePlanSummary() -> TerraCoreMLComputePlanSummary {
  TerraCoreMLComputePlanSummary(
    captureStatus: .unsupportedOS,
    modelStructure: "unsupported",
    estimatedPrimaryDevice: "unknown",
    supportedDevices: [],
    nodeCount: 0,
    captureDurationMS: 0,
    operationEstimates: [],
    errorType: nil
  )
}
#endif

@Suite("TerraSession beta ship behavior", .serialized)
struct TerraSessionTests {
  @Test("TerraSession start/end emits root session span metadata and simulator warning")
  func sessionStartEndMetadata() async throws {
    Terra.lockTestingIsolation()
    defer { Terra.unlockTestingIsolation() }

    let harness = SessionSpanHarness()
    defer { harness.tearDown() }

    var configuration = TerraSession.Configuration()
    configuration.memorySamplingInterval = nil
    configuration.autoStartRuntime = false

    let logger = TestSessionLogger()
    let session = TerraSession(
      configuration: configuration,
      dependencies: .init(
        dashboardDiscovery: MockDashboardDiscovery(endpoint: nil),
        logger: logger,
        isSimulator: true,
        currentThermalState: { ProcessInfo.ThermalState.serious },
        memoryFootprint: { Optional<UInt64>.none }
      )
    )

    try await session.start()
    await session.end()

    let sessionSpan = try #require(harness.finishedSpans().first(where: { $0.name == "terra.session" }))
    #expect(sessionSpan.attributes["terra.session.id"] != nil)
    #expect(sessionSpan.attributes["terra.session.device_model"] != nil)
    #expect(sessionSpan.attributes["terra.session.os_version"] != nil)
    #expect(sessionSpan.attributes["terra.device.is_simulator"]?.description == "true")
    #expect(sessionSpan.attributes[Terra.Keys.Terra.thermalState]?.description == "serious")
    #expect(sessionSpan.events.contains(where: { $0.name == "terra.warning" }))
    #expect(logger.warnings.contains(where: { $0.localizedCaseInsensitiveContains("Simulator") }))
  }

  @Test("TerraSession records thermal transitions, memory samples, and memory warnings on the session span")
  func sessionRecordsThermalAndMemoryEvents() async throws {
    Terra.lockTestingIsolation()
    defer { Terra.unlockTestingIsolation() }

    let harness = SessionSpanHarness()
    defer { harness.tearDown() }

    var configuration = TerraSession.Configuration()
    configuration.memorySamplingInterval = nil
    configuration.autoStartRuntime = false

    let session = TerraSession(
      configuration: configuration,
      dependencies: .init(
        dashboardDiscovery: MockDashboardDiscovery(endpoint: nil),
        logger: TestSessionLogger(),
        isSimulator: false,
        currentThermalState: { ProcessInfo.ThermalState.nominal },
        memoryFootprint: { 84 * 1_048_576 }
      )
    )

    try await session.start()
    await session.recordThermalTransition(to: ProcessInfo.ThermalState.fair)
    await session.recordMemorySample(reason: TerraSession.MemorySampleReason.timer)
    await session.recordMemoryWarning()
    await session.end()

    let sessionSpan = try #require(harness.finishedSpans().first(where: { $0.name == "terra.session" }))
    #expect(sessionSpan.events.contains(where: { $0.name == "terra.thermal.transition" }))
    #expect(sessionSpan.events.contains(where: { $0.name == "terra.memory.sample" }))
    #expect(sessionSpan.events.contains(where: { $0.name == "terra.memory.warning" }))
  }

  @Test("TerraSession marks simulator session spans as local-only when export is disabled")
  func sessionMarksSimulatorSpansLocalOnly() async throws {
    Terra.lockTestingIsolation()
    defer { Terra.unlockTestingIsolation() }

    let harness = SessionSpanHarness()
    defer { harness.tearDown() }

    var configuration = TerraSession.Configuration()
    configuration.memorySamplingInterval = nil
    configuration.autoStartRuntime = false

    let session = TerraSession(
      configuration: configuration,
      dependencies: .init(
        dashboardDiscovery: MockDashboardDiscovery(endpoint: nil),
        logger: TestSessionLogger(),
        isSimulator: true,
        currentThermalState: { ProcessInfo.ThermalState.nominal },
        memoryFootprint: { Optional<UInt64>.none }
      )
    )

    try await session.start()
    _ = try await session.recordInference(
      modelName: "SimulatorModel",
      featureSummaries: []
    ) {
      "ok"
    }
    await session.end()

    let sessionSpan = try #require(harness.finishedSpans().first(where: { $0.name == Terra.SpanNames.session }))
    let inferenceSpan = try #require(harness.finishedSpans().first(where: { $0.name == Terra.SpanNames.inference }))
    #expect(sessionSpan.attributes[Terra.Keys.Terra.exportLocalOnly] == .bool(true))
    #expect(inferenceSpan.attributes[Terra.Keys.Terra.exportLocalOnly] == .bool(true))
  }

  @Test("TerraSession leaves the process-wide export gate unchanged")
  func sessionLeavesGlobalExportGateUntouched() async throws {
    Terra.lockTestingIsolation()
    defer { Terra.unlockTestingIsolation() }
    Terra._setSimulatorExportBlocked(true)
    defer { Terra._setSimulatorExportBlocked(false) }

    var configuration = TerraSession.Configuration()
    configuration.memorySamplingInterval = nil
    configuration.autoStartRuntime = false

    let session = TerraSession(
      configuration: configuration,
      dependencies: .init(
        dashboardDiscovery: MockDashboardDiscovery(endpoint: nil),
        logger: TestSessionLogger(),
        isSimulator: true,
        currentThermalState: { ProcessInfo.ThermalState.nominal },
        memoryFootprint: { Optional<UInt64>.none },
        isRuntimeRunning: { true }
      )
    )

    try await session.start()
    #expect(Terra._isSimulatorExportBlocked == true)
    await session.end()
    #expect(Terra._isSimulatorExportBlocked == true)
  }

  @Test("TerraSession simulator export opt-in keeps session spans exportable")
  func sessionOptInLeavesSimulatorSpansExportable() async throws {
    Terra.lockTestingIsolation()
    defer { Terra.unlockTestingIsolation() }

    let harness = SessionSpanHarness()
    defer { harness.tearDown() }

    var configuration = TerraSession.Configuration()
    configuration.memorySamplingInterval = nil
    configuration.autoStartRuntime = false
    configuration.exportSimulatorMetrics = true

    let session = TerraSession(
      configuration: configuration,
      dependencies: .init(
        dashboardDiscovery: MockDashboardDiscovery(endpoint: nil),
        logger: TestSessionLogger(),
        isSimulator: true,
        currentThermalState: { ProcessInfo.ThermalState.nominal },
        memoryFootprint: { Optional<UInt64>.none }
      )
    )

    try await session.start()
    _ = try await session.recordInference(
      modelName: "OptInModel",
      featureSummaries: []
    ) {
      "ok"
    }
    await session.end()

    let sessionSpan = try #require(harness.finishedSpans().first(where: { $0.name == Terra.SpanNames.session }))
    let inferenceSpan = try #require(harness.finishedSpans().first(where: { $0.name == Terra.SpanNames.inference }))
    #expect(sessionSpan.attributes[Terra.Keys.Terra.exportLocalOnly] == nil)
    #expect(inferenceSpan.attributes[Terra.Keys.Terra.exportLocalOnly] == nil)
  }

  @Test("TerraSession resolves a discovered dashboard endpoint and falls back when unavailable")
  func sessionResolvesDashboardEndpoint() async throws {
    var configuration = TerraSession.Configuration()
    configuration.autoStartRuntime = false

    let discovered = TerraSession(
      configuration: configuration,
      dependencies: .init(
        dashboardDiscovery: MockDashboardDiscovery(endpoint: URL(string: "http://10.0.0.8:4318")!),
        logger: TestSessionLogger(),
        isSimulator: false,
        currentThermalState: { ProcessInfo.ThermalState.nominal },
        memoryFootprint: { Optional<UInt64>.none }
      )
    )
    let fallback = TerraSession(
      configuration: configuration,
      dependencies: .init(
        dashboardDiscovery: MockDashboardDiscovery(endpoint: nil),
        logger: TestSessionLogger(),
        isSimulator: false,
        currentThermalState: { ProcessInfo.ThermalState.nominal },
        memoryFootprint: { Optional<UInt64>.none },
        computePlanSummary: { _, _ in
          unsupportedComputePlanSummary()
        }
      )
    )

    #expect(await discovered.resolveExporterEndpoint()?.absoluteString == "http://10.0.0.8:4318")
    #expect(await fallback.resolveExporterEndpoint()?.absoluteString == "http://127.0.0.1:4318")
  }

  @Test("TerraSession model load records cold then warm spans and compute units")
  func sessionModelLoadTracking() async throws {
    Terra.lockTestingIsolation()
    defer { Terra.unlockTestingIsolation() }

    let harness = SessionSpanHarness()
    defer { harness.tearDown() }

    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TerraSessionTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let modelURL = tempDirectory.appendingPathComponent("Demo.mlmodelc")
    try Data("demo".utf8).write(to: modelURL)

    var configuration = TerraSession.Configuration()
    configuration.memorySamplingInterval = nil
    configuration.autoStartRuntime = false
    configuration.modelLoadCacheURL = tempDirectory.appendingPathComponent("load-cache.json")

    let session = TerraSession(
      configuration: configuration,
      dependencies: .init(
        dashboardDiscovery: MockDashboardDiscovery(endpoint: nil),
        logger: TestSessionLogger(),
        isSimulator: false,
        currentThermalState: { ProcessInfo.ThermalState.nominal },
        memoryFootprint: { Optional<UInt64>.none },
        computePlanSummary: { _, _ in
          TerraCoreMLComputePlanSummary(
            captureStatus: .unsupportedOS,
            modelStructure: "unsupported",
            estimatedPrimaryDevice: "unknown",
            supportedDevices: [],
            nodeCount: 0,
            captureDurationMS: 0,
            operationEstimates: [],
            errorType: nil
          )
        }
      )
    )

    try await session.start()
    let configurationObject = MLModelConfiguration()
    configurationObject.computeUnits = .cpuAndGPU

    _ = try await session.recordModelLoad(
      contentsOf: modelURL,
      configuration: configurationObject,
      modelName: "DemoModel"
    ) {
      "fake-model"
    }
    _ = try await session.recordModelLoad(
      contentsOf: modelURL,
      configuration: configurationObject,
      modelName: "DemoModel"
    ) {
      "fake-model"
    }
    await session.end()

    let spans = harness.finishedSpans().filter { $0.name == Terra.SpanNames.modelLoad }
    let coldSpan = try #require(spans.first)
    let warmSpan = try #require(spans.dropFirst().first)
    #expect(coldSpan.attributes["terra.coreml.load.is_cold"]?.description == "true")
    #expect(warmSpan.attributes["terra.coreml.load.is_cold"]?.description == "false")
    #expect(coldSpan.attributes["terra.coreml.compute_units"]?.description == "cpu_and_gpu")
  }

  @Test("TerraSession model load records MLComputePlan estimate metadata when available")
  func sessionModelLoadRecordsComputePlanEstimate() async throws {
    Terra.lockTestingIsolation()
    defer { Terra.unlockTestingIsolation() }

    let harness = SessionSpanHarness()
    defer { harness.tearDown() }

    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TerraSessionComputePlanTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let modelURL = tempDirectory.appendingPathComponent("Plan.mlmodelc")
    try Data("demo".utf8).write(to: modelURL)

    var configuration = TerraSession.Configuration()
    configuration.memorySamplingInterval = nil
    configuration.autoStartRuntime = false
    configuration.modelLoadCacheURL = tempDirectory.appendingPathComponent("load-cache.json")

    let summary = TerraCoreMLComputePlanSummary(
      captureStatus: .captured,
      modelStructure: "program",
      estimatedPrimaryDevice: "ane",
      supportedDevices: ["ane", "cpu"],
      nodeCount: 2,
      captureDurationMS: 3.5,
      operationEstimates: [
        .init(identifier: "program.main.op0.conv", kind: "program_operation", preferredDevice: "ane", supportedDevices: ["ane", "cpu"]),
        .init(identifier: "program.main.op1.softmax", kind: "program_operation", preferredDevice: "cpu", supportedDevices: ["cpu"]),
      ],
      errorType: nil
    )

    let session = TerraSession(
      configuration: configuration,
      dependencies: .init(
        dashboardDiscovery: MockDashboardDiscovery(endpoint: nil),
        logger: TestSessionLogger(),
        isSimulator: false,
        currentThermalState: { ProcessInfo.ThermalState.nominal },
        memoryFootprint: { Optional<UInt64>.none },
        computePlanSummary: { _, _ in summary }
      )
    )

    try await session.start()
    _ = try await session.recordModelLoad(
      contentsOf: modelURL,
      configuration: MLModelConfiguration(),
      modelName: "PlanModel"
    ) {
      "fake-model"
    }
    await session.end()

    let span = try #require(harness.finishedSpans().first(where: { $0.name == Terra.SpanNames.modelLoad }))
    #expect(span.attributes[TerraCoreML.Keys.computePlanCaptureStatus]?.description == "captured")
    #expect(span.attributes[TerraCoreML.Keys.computePlanEstimatedPrimaryDevice]?.description == "ane")
    #expect(span.attributes[TerraCoreML.Keys.computePlanEstimatedOperations]?.description.contains("program.main.op0.conv") == true)
  }

  @Test("TerraSession model load duration includes compute-plan capture time")
  func sessionModelLoadDurationIncludesComputePlanCapture() async throws {
    Terra.lockTestingIsolation()
    defer { Terra.unlockTestingIsolation() }

    let harness = SessionSpanHarness()
    defer { harness.tearDown() }

    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TerraSessionTimingTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let modelURL = tempDirectory.appendingPathComponent("Timing.mlmodelc")
    try Data("demo".utf8).write(to: modelURL)

    var configuration = TerraSession.Configuration()
    configuration.memorySamplingInterval = nil
    configuration.autoStartRuntime = false
    configuration.modelLoadCacheURL = tempDirectory.appendingPathComponent("load-cache.json")

    let session = TerraSession(
      configuration: configuration,
      dependencies: .init(
        dashboardDiscovery: MockDashboardDiscovery(endpoint: nil),
        logger: TestSessionLogger(),
        isSimulator: false,
        currentThermalState: { ProcessInfo.ThermalState.nominal },
        memoryFootprint: { Optional<UInt64>.none },
        computePlanSummary: { _, _ in
          try? await Task.sleep(nanoseconds: 50_000_000)
          return unsupportedComputePlanSummary()
        }
      )
    )

    try await session.start()
    _ = try await session.recordModelLoad(
      contentsOf: modelURL,
      configuration: MLModelConfiguration(),
      modelName: "TimingModel"
    ) {
      "fake-model"
    }
    await session.end()

    let span = try #require(harness.finishedSpans().first(where: { $0.name == Terra.SpanNames.modelLoad }))
    let duration = Double(span.attributes["terra.coreml.load.duration_ms"]?.description ?? "")
    let measuredDuration = try #require(duration)
    #expect(measuredDuration >= 45)
  }

  @Test("TerraSession model load cache keys vary by model configuration")
  func sessionModelLoadCacheKeyIncludesConfiguration() async throws {
    Terra.lockTestingIsolation()
    defer { Terra.unlockTestingIsolation() }

    let harness = SessionSpanHarness()
    defer { harness.tearDown() }

    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TerraSessionCacheKeyTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let modelURL = tempDirectory.appendingPathComponent("Config.mlmodelc")
    try Data("demo".utf8).write(to: modelURL)

    var configuration = TerraSession.Configuration()
    configuration.memorySamplingInterval = nil
    configuration.autoStartRuntime = false
    configuration.modelLoadCacheURL = tempDirectory.appendingPathComponent("load-cache.json")

    let session = TerraSession(
      configuration: configuration,
      dependencies: .init(
        dashboardDiscovery: MockDashboardDiscovery(endpoint: nil),
        logger: TestSessionLogger(),
        isSimulator: false,
        currentThermalState: { ProcessInfo.ThermalState.nominal },
        memoryFootprint: { Optional<UInt64>.none },
        computePlanSummary: { _, _ in
          unsupportedComputePlanSummary()
        }
      )
    )

    let cpuOnly = MLModelConfiguration()
    cpuOnly.computeUnits = .cpuOnly
    let cpuAndANE = MLModelConfiguration()
    cpuAndANE.computeUnits = .cpuAndNeuralEngine

    try await session.start()
    _ = try await session.recordModelLoad(
      contentsOf: modelURL,
      configuration: cpuOnly,
      modelName: "ConfigModel"
    ) {
      "cpu-only"
    }
    _ = try await session.recordModelLoad(
      contentsOf: modelURL,
      configuration: cpuAndANE,
      modelName: "ConfigModel"
    ) {
      "cpu-ane"
    }
    await session.end()

    let spans = harness.finishedSpans().filter { $0.name == Terra.SpanNames.modelLoad }
    let firstSpan = try #require(spans.first)
    let secondSpan = try #require(spans.dropFirst().first)
    #expect(firstSpan.attributes["terra.coreml.load.is_cold"] == .bool(true))
    #expect(secondSpan.attributes["terra.coreml.load.is_cold"] == .bool(true))
    #expect(firstSpan.attributes["terra.coreml.load.cache_key"] != secondSpan.attributes["terra.coreml.load.cache_key"])
  }

  @Test("TerraSession inference tracking records feature summaries, thermal state, and error type")
  func sessionInferenceTracking() async throws {
    Terra.lockTestingIsolation()
    defer { Terra.unlockTestingIsolation() }

    let harness = SessionSpanHarness()
    defer { harness.tearDown() }

    var configuration = TerraSession.Configuration()
    configuration.memorySamplingInterval = nil
    configuration.autoStartRuntime = false

    let session = TerraSession(
      configuration: configuration,
      dependencies: .init(
        dashboardDiscovery: MockDashboardDiscovery(endpoint: nil),
        logger: TestSessionLogger(),
        isSimulator: false,
        currentThermalState: { ProcessInfo.ThermalState.critical },
        memoryFootprint: { Optional<UInt64>.none }
      )
    )

    try await session.start()
    await #expect(throws: InferenceFailure.self) {
      _ = try await session.recordInference(
        modelName: "DemoModel",
        featureSummaries: [
          .init(name: "tokens", kind: "multi_array", shape: [1, 16]),
          .init(name: "mask", kind: "image", shape: [224, 224, 3]),
        ]
      ) {
        throw InferenceFailure.failed
      }
    }
    await session.end()

    let span = try #require(harness.finishedSpans().first(where: {
      $0.name == Terra.SpanNames.inference && $0.attributes[Terra.Keys.GenAI.requestModel]?.description == "DemoModel"
    }))
    #expect(span.attributes[Terra.Keys.Terra.thermalState]?.description == "critical")
    #expect(span.attributes["terra.coreml.error_type"]?.description == String(reflecting: InferenceFailure.self))
    #expect(span.attributes["terra.coreml.input_summary"]?.description.contains("\"tokens\"") == true)
    #expect(span.attributes["terra.coreml.input_summary"]?.description.contains("[1,16]") == true)
  }

  @Test("TerraSession spans persist and reload as a complete session trace")
  func sessionTraceRoundTrip() async throws {
    Terra.lockTestingIsolation()
    defer { Terra.unlockTestingIsolation() }

    let harness = SessionSpanHarness()
    defer { harness.tearDown() }

    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TerraSessionTraceTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    var configuration = TerraSession.Configuration()
    configuration.memorySamplingInterval = nil
    configuration.autoStartRuntime = false
    configuration.modelLoadCacheURL = tempDirectory.appendingPathComponent("load-cache.json")

    let session = TerraSession(
      configuration: configuration,
      dependencies: .init(
        dashboardDiscovery: MockDashboardDiscovery(endpoint: nil),
        logger: TestSessionLogger(),
        isSimulator: false,
        currentThermalState: { ProcessInfo.ThermalState.nominal },
        memoryFootprint: { 42 * 1_048_576 },
        computePlanSummary: { _, _ in
          unsupportedComputePlanSummary()
        }
      )
    )

    try await session.start()
    await session.recordThermalTransition(to: .fair)
    await session.recordMemorySample(reason: .timer)

    let modelURL = tempDirectory.appendingPathComponent("Replayable.mlmodelc")
    try Data("demo".utf8).write(to: modelURL)

    let modelConfiguration = MLModelConfiguration()
    modelConfiguration.computeUnits = .cpuOnly

    _ = try await session.recordModelLoad(
      contentsOf: modelURL,
      configuration: modelConfiguration,
      modelName: "Replayable"
    ) {
      "fake-model"
    }

    _ = try await session.recordInference(
      modelName: "Replayable",
      featureSummaries: [.init(name: "tokens", kind: "multi_array", shape: [1, 8])],
      computeUnits: .cpuOnly
    ) {
      "ok"
    }
    await session.end()

    let spans = harness.finishedSpans()
    let encoded = try JSONEncoder().encode(spans)
    var persisted = Data(encoded)
    persisted.append(Data(",".utf8))
    try persisted.write(to: tempDirectory.appendingPathComponent("1000"))

    let loader = TraceLoader(locator: TraceFileLocator(tracesDirectoryURL: tempDirectory))
    let result = try loader.loadTracesWithFailures()

    #expect(result.failures.isEmpty)
    #expect(result.traces.count == 1)

    let loadedTrace = try #require(result.traces.first)
    let sessionSpan = try #require(loadedTrace.spans.first(where: { $0.name == Terra.SpanNames.session }))
    #expect(sessionSpan.events.contains(where: { $0.name == "terra.thermal.transition" }))
    #expect(sessionSpan.events.contains(where: { $0.name == "terra.memory.sample" }))
    #expect(loadedTrace.spans.contains(where: { $0.name == Terra.SpanNames.modelLoad }))
    #expect(loadedTrace.spans.contains(where: { $0.name == Terra.SpanNames.inference }))
  }

  @Test("BonjourTerraDashboardDiscovery completes within the timeout window when no service resolves")
  func bonjourDiscoveryTimesOutWithoutHanging() async {
    let discovery = BonjourTerraDashboardDiscovery()

    let completed = await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        _ = await discovery.discoverEndpoint(timeout: .milliseconds(50))
        return true
      }
      group.addTask {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        return false
      }

      let result = await group.next() ?? false
      group.cancelAll()
      return result
    }

    #expect(completed)
  }

  @Test("TerraSessionModelLoadCacheStore merges concurrent writes for a shared cache file")
  func modelLoadCacheStoreMergesConcurrentWrites() async throws {
    let store = TerraSessionModelLoadCacheStore()

    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TerraSessionCacheStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let cacheURL = tempDirectory.appendingPathComponent("load-cache.json")

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await store.markWarm(cacheKey: "model-a", fileURL: cacheURL)
      }
      group.addTask {
        try await store.markWarm(cacheKey: "model-b", fileURL: cacheURL)
      }
      try await group.waitForAll()
    }

    #expect(await store.isCold(cacheKey: "model-a", fileURL: cacheURL) == false)
    #expect(await store.isCold(cacheKey: "model-b", fileURL: cacheURL) == false)

    let persisted = try JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: cacheURL))
    #expect(persisted == ["model-a", "model-b"])
  }
}
