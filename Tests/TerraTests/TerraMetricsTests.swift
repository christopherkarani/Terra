import OpenTelemetryApi
import OpenTelemetrySdk
@testable import Terra
import XCTest

final class TerraMetricsTests: XCTestCase {
  final class MetricExporterSpy: MetricExporter {
    private let lock = NSLock()
    private var exported: [MetricData] = []

    func export(metrics: [MetricData]) -> ExportResult {
      lock.lock()
      exported.append(contentsOf: metrics)
      lock.unlock()
      return .success
    }

    func flush() -> ExportResult { .success }
    func shutdown() -> ExportResult { .success }
    func getAggregationTemporality(for instrument: InstrumentType) -> AggregationTemporality { .cumulative }

    var exportedMetrics: [MetricData] {
      lock.lock()
      defer { lock.unlock() }
      return exported
    }
  }

  func testRecordInference_emitsCountAndDurationMetrics() {
    let exporter = MetricExporterSpy()
    let reader = PeriodicMetricReaderBuilder(exporter: exporter)
      .setInterval(timeInterval: 0.01)
      .build()
    let meterProvider = MeterProviderSdk.builder()
      .registerMetricReader(reader: reader)
      .build()

    let metrics = TerraMetrics()
    metrics.configure(meterProvider: meterProvider)
    metrics.recordInference(durationMs: 12.5)

    XCTAssertEqual(meterProvider.forceFlush(), .success)
    _ = reader.shutdown()

    _ = exporter.exportedMetrics
  }

  func testInstall_withoutExplicitMeterProvider_usesGlobalMeterProvider() async {
    let exporter = MetricExporterSpy()
    let reader = PeriodicMetricReaderBuilder(exporter: exporter)
      .setInterval(timeInterval: 0.01)
      .build()
    let meterProvider = MeterProviderSdk.builder()
      .registerMetricReader(reader: reader)
      .build()

    let previousMeterProvider = OpenTelemetry.instance.meterProvider
    OpenTelemetry.registerMeterProvider(meterProvider: meterProvider)
    defer {
      OpenTelemetry.registerMeterProvider(meterProvider: previousMeterProvider)
      Terra.install(.init(meterProvider: nil, registerProvidersAsGlobal: false))
      _ = reader.shutdown()
    }

    Terra.install(.init(meterProvider: nil, registerProvidersAsGlobal: false))
    await Terra.withInferenceSpan(.init(model: "local/llama-3.2-1b")) { _ in }

    XCTAssertEqual(meterProvider.forceFlush(), .success)
    XCTAssertFalse(exporter.exportedMetrics.isEmpty)
  }
}
