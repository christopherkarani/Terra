import XCTest
import InMemoryExporter
import OpenTelemetryApi
import OpenTelemetrySdk
import PersistenceExporter
@testable import TerraCore

final class TerraLifecycleTests: XCTestCase {

  override func setUp() async throws {
    // Reset both the OTel install state and the Runtime lifecycle state before each test.
    Terra.resetOpenTelemetryForTesting()
  }

  override func tearDown() async throws {
    // Shut down if anything was installed during the test.
    Terra._shutdownOpenTelemetry()
  }

  // MARK: - State Query Tests

  func testInitialState_isStopped() {
    XCTAssertEqual(Terra._lifecycleState, .stopped)
    XCTAssertFalse(Terra._isRunning)
  }

  func testAfterInstall_isRunning() throws {
    let config = minimalConfig()
    try Terra.installOpenTelemetry(config)
    XCTAssertEqual(Terra._lifecycleState, .running)
    XCTAssertTrue(Terra._isRunning)
  }

  func testAfterShutdown_isStopped() async throws {
    try Terra.installOpenTelemetry(minimalConfig())
    XCTAssertTrue(Terra._isRunning)

    Terra._shutdownOpenTelemetry()

    XCTAssertEqual(Terra._lifecycleState, .stopped)
    XCTAssertFalse(Terra._isRunning)
  }

  func testShutdown_whenNotRunning_isIdempotent() async {
    XCTAssertFalse(Terra._isRunning)
    Terra._shutdownOpenTelemetry()  // no-op: must not crash
    Terra._shutdownOpenTelemetry()  // second call: must not crash
    XCTAssertFalse(Terra._isRunning)
  }

  func testShutdown_isIdempotent_afterInstall() async throws {
    try Terra.installOpenTelemetry(minimalConfig())
    Terra._shutdownOpenTelemetry()
    Terra._shutdownOpenTelemetry()  // second call: must not crash
    XCTAssertFalse(Terra._isRunning)
  }

  func testStartAfterShutdown_succeeds() async throws {
    let config1 = minimalConfig(port: 14001)
    let config2 = minimalConfig(port: 14002)

    try Terra.installOpenTelemetry(config1)
    XCTAssertTrue(Terra._isRunning)

    Terra._shutdownOpenTelemetry()
    XCTAssertFalse(Terra._isRunning)

    // Must succeed — state is stopped after shutdown
    XCTAssertNoThrow(try Terra.installOpenTelemetry(config2))
    XCTAssertTrue(Terra._isRunning)
  }

  func testStartSameConfig_isIdempotent() throws {
    let config = minimalConfig()
    try Terra.installOpenTelemetry(config)
    // Second call with identical config: no throw, stays running
    XCTAssertNoThrow(try Terra.installOpenTelemetry(config))
    XCTAssertTrue(Terra._isRunning)
  }

  func testStartDifferentConfig_throwsAlreadyInstalled() throws {
    let config1 = minimalConfig(port: 14001)
    let config2 = minimalConfig(port: 14002)
    try Terra.installOpenTelemetry(config1)
    XCTAssertThrowsError(try Terra.installOpenTelemetry(config2)) { error in
      XCTAssertEqual(error as? Terra.InstallOpenTelemetryError, .alreadyInstalled)
    }
  }

  func testShutdown_withAugmentExistingStrategy_leavesStateStopped() async throws {
    // .augmentExisting borrows the existing global provider; Terra must not
    // call shutdown() on it, but must still transition its own lifecycle state.
    var config = minimalConfig()
    // We can't easily verify the borrowed provider is not shut down without
    // deeper OTel SDK inspection, so we assert the lifecycle contract:
    // after shutdown Terra is .stopped and a fresh install is allowed.
    config = Terra.OpenTelemetryConfiguration(
      tracerProviderStrategy: .augmentExisting,
      enableTraces: false,
      enableMetrics: false,
      enableLogs: false,
      enableSignposts: false,
      enableSessions: false,
      otlpTracesEndpoint: URL(string: "http://127.0.0.1:14098/v1/traces")!,
      otlpMetricsEndpoint: URL(string: "http://127.0.0.1:14098/v1/metrics")!,
      otlpLogsEndpoint: URL(string: "http://127.0.0.1:14098/v1/logs")!
    )

    XCTAssertNoThrow(try Terra.installOpenTelemetry(config))
    XCTAssertTrue(Terra._isRunning)

    Terra._shutdownOpenTelemetry()

    XCTAssertFalse(Terra._isRunning)
    XCTAssertEqual(Terra._lifecycleState, .stopped)

    // Fresh install must succeed after augmentExisting shutdown
    XCTAssertNoThrow(try Terra.installOpenTelemetry(minimalConfig(port: 14097)))
    XCTAssertTrue(Terra._isRunning)
  }

  func testSimulatorAwareSpanExporter_skipsExportUntilEnabled() {
    let gate = TestExportGate(shouldExport: false)
    let base = CountingSpanExporter()
    let exporter = Terra.SimulatorAwareSpanExporter(
      spanExporter: base,
      shouldExport: { gate.shouldExport }
    )
    let span = makeSpanData(name: "gated-span")

    XCTAssertEqual(exporter.export(spans: [span], explicitTimeout: nil), .success)
    XCTAssertEqual(exporter.flush(explicitTimeout: nil), .success)
    XCTAssertEqual(base.exportCalls, 0)
    XCTAssertEqual(base.flushCalls, 0)

    gate.shouldExport = true

    XCTAssertEqual(exporter.export(spans: [span], explicitTimeout: nil), .success)
    XCTAssertEqual(exporter.flush(explicitTimeout: nil), .success)
    exporter.shutdown(explicitTimeout: nil)

    XCTAssertEqual(base.exportCalls, 1)
    XCTAssertEqual(base.flushCalls, 1)
    XCTAssertEqual(base.shutdownCalls, 1)
  }

  func testSimulatorAwareSpanExporter_filtersLocalOnlySpans() {
    let base = CountingSpanExporter()
    let exporter = Terra.SimulatorAwareSpanExporter(
      spanExporter: base,
      shouldExport: { true }
    )

    let localOnlySpan = makeSpanData(
      name: "local-only",
      attributes: [Terra.Keys.Terra.exportLocalOnly: .bool(true)]
    )
    let exportableSpan = makeSpanData(name: "remote")

    XCTAssertEqual(exporter.export(spans: [localOnlySpan], explicitTimeout: nil), .success)
    XCTAssertTrue(base.exportedSpans.isEmpty)

    XCTAssertEqual(exporter.export(spans: [localOnlySpan, exportableSpan], explicitTimeout: nil), .success)
    XCTAssertEqual(base.exportedSpans.count, 1)
    XCTAssertEqual(base.exportedSpans.first?.name, "remote")
  }

  func testSimulatorAwareMetricExporter_skipsExportUntilEnabled() {
    let gate = TestExportGate(shouldExport: false)
    let base = CountingMetricExporter()
    let exporter = Terra.SimulatorAwareMetricExporter(
      metricExporter: base,
      shouldExport: { gate.shouldExport }
    )

    XCTAssertEqual(exporter.export(metrics: []), .success)
    XCTAssertEqual(exporter.flush(), .success)
    XCTAssertEqual(base.exportCalls, 0)
    XCTAssertEqual(base.flushCalls, 0)

    gate.shouldExport = true

    XCTAssertEqual(exporter.export(metrics: []), .success)
    XCTAssertEqual(exporter.flush(), .success)
    XCTAssertEqual(exporter.shutdown(), .success)

    XCTAssertEqual(base.exportCalls, 1)
    XCTAssertEqual(base.flushCalls, 1)
    XCTAssertEqual(base.shutdownCalls, 1)
  }

  func testSimulatorAwareLogExporter_skipsExportUntilEnabled() {
    let gate = TestExportGate(shouldExport: false)
    let base = CountingLogRecordExporter()
    let exporter = Terra.SimulatorAwareLogExporter(
      logExporter: base,
      shouldExport: { gate.shouldExport }
    )
    let logRecord = makeLogRecord()

    XCTAssertEqual(exporter.export(logRecords: [logRecord], explicitTimeout: nil), .success)
    XCTAssertEqual(base.exportCalls, 0)

    gate.shouldExport = true

    XCTAssertEqual(exporter.export(logRecords: [logRecord], explicitTimeout: nil), .success)
    exporter.shutdown(explicitTimeout: nil)

    XCTAssertEqual(base.exportCalls, 1)
    XCTAssertEqual(base.shutdownCalls, 1)
  }

  func testPersistenceSpanExporterDecorator_persistsLocalOnlyTraces() throws {
    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TerraLifecyclePersistence-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let base = CountingSpanExporter()
    let exporter = try PersistenceSpanExporterDecorator(
      spanExporter: Terra.SimulatorAwareSpanExporter(
        spanExporter: base,
        shouldExport: { true }
      ),
      storageURL: tempDirectory,
      performancePreset: synchronousPersistencePreset()
    )

    XCTAssertEqual(
      exporter.export(
        spans: [
          makeSpanData(
            name: "persisted.local.only",
            attributes: [Terra.Keys.Terra.exportLocalOnly: .bool(true)]
          )
        ],
        explicitTimeout: nil
      ),
      .success
    )
    XCTAssertEqual(base.exportCalls, 0)

    let persistedFiles = try FileManager.default.contentsOfDirectory(
      at: tempDirectory,
      includingPropertiesForKeys: nil
    )
    XCTAssertFalse(persistedFiles.isEmpty)

    let persistedData = try Data(contentsOf: persistedFiles[0])
    XCTAssertFalse(persistedData.isEmpty)
  }
}

// MARK: - Helpers

private func minimalConfig(port: Int = 14099) -> Terra.OpenTelemetryConfiguration {
  Terra.OpenTelemetryConfiguration(
    enableTraces: false,
    enableMetrics: false,
    enableLogs: false,
    enableSignposts: false,
    enableSessions: false,
    otlpTracesEndpoint: URL(string: "http://127.0.0.1:\(port)/v1/traces")!,
    otlpMetricsEndpoint: URL(string: "http://127.0.0.1:\(port)/v1/metrics")!,
    otlpLogsEndpoint: URL(string: "http://127.0.0.1:\(port)/v1/logs")!
  )
}

private func makeSpanData(
  name: String,
  attributes: [String: AttributeValue] = [:]
) -> SpanData {
  let exporter = InMemoryExporter()
  let provider = TracerProviderSdk()
  provider.addSpanProcessor(SimpleSpanProcessor(spanExporter: exporter))
  let tracer = provider.get(instrumentationName: "TerraLifecycleTests.makeSpanData")
  let span = tracer.spanBuilder(spanName: name).startSpan()
  span.setAttributes(attributes)
  span.end()
  provider.forceFlush()
  return exporter.getFinishedSpanItems()[0]
}

private func makeLogRecord(
  attributes: [String: AttributeValue] = [:]
) -> ReadableLogRecord {
  ReadableLogRecord(
    resource: Resource(attributes: [:]),
    instrumentationScopeInfo: InstrumentationScopeInfo(),
    timestamp: Date(),
    attributes: attributes
  )
}

private func synchronousPersistencePreset() -> PersistencePerformancePreset {
  PersistencePerformancePreset(
    maxFileSize: 64 * 1_024,
    maxDirectorySize: 4 * 1_024 * 1_024,
    maxFileAgeForWrite: 60,
    minFileAgeForRead: 120,
    maxFileAgeForRead: 600,
    maxObjectsInFile: 100,
    maxObjectSize: 64 * 1_024,
    synchronousWrite: true,
    initialExportDelay: 300,
    defaultExportDelay: 300,
    minExportDelay: 300,
    maxExportDelay: 300,
    exportDelayChangeRate: 0
  )
}

private final class CountingSpanExporter: SpanExporter {
  private(set) var exportCalls = 0
  private(set) var flushCalls = 0
  private(set) var shutdownCalls = 0
  private(set) var exportedSpans: [SpanData] = []

  func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
    exportedSpans.append(contentsOf: spans)
    _ = explicitTimeout
    exportCalls += 1
    return .success
  }

  func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
    _ = explicitTimeout
    flushCalls += 1
    return .success
  }

  func shutdown(explicitTimeout: TimeInterval?) {
    _ = explicitTimeout
    shutdownCalls += 1
  }
}

private final class CountingMetricExporter: MetricExporter {
  private(set) var exportCalls = 0
  private(set) var flushCalls = 0
  private(set) var shutdownCalls = 0

  func export(metrics: [MetricData]) -> ExportResult {
    _ = metrics
    exportCalls += 1
    return .success
  }

  func flush() -> ExportResult {
    flushCalls += 1
    return .success
  }

  func shutdown() -> ExportResult {
    shutdownCalls += 1
    return .success
  }

  func getAggregationTemporality(for instrument: InstrumentType) -> AggregationTemporality {
    _ = instrument
    return .cumulative
  }
}

private final class CountingLogRecordExporter: LogRecordExporter {
  private(set) var exportCalls = 0
  private(set) var shutdownCalls = 0
  private(set) var forceFlushCalls = 0

  func export(logRecords: [ReadableLogRecord], explicitTimeout: TimeInterval?) -> ExportResult {
    _ = logRecords
    _ = explicitTimeout
    exportCalls += 1
    return .success
  }

  func shutdown(explicitTimeout: TimeInterval?) {
    _ = explicitTimeout
    shutdownCalls += 1
  }

  func forceFlush(explicitTimeout: TimeInterval?) -> ExportResult {
    _ = explicitTimeout
    forceFlushCalls += 1
    return .success
  }
}

private final class TestExportGate: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Bool

  init(shouldExport: Bool) {
    self.value = shouldExport
  }

  var shouldExport: Bool {
    get { lock.withLock { value } }
    set { lock.withLock { value = newValue } }
  }
}
