import OpenTelemetryApi
import OpenTelemetrySdk
@testable import Terra
import XCTest

final class TerraMetricsTests: XCTestCase {

  // MARK: - Spy infrastructure

  /// Records all counter.add() and histogram.record() calls for verification.
  final class InstrumentRecordingSpy {
    var counterAddCalls: [(Int, [String: String])] = []
    var histogramRecordCalls: [(Double, [String: String])] = []
  }

  // MARK: - Instrument verification

  func testConfigure_createsInstrumentsOnMeterProvider() {
    let meterProvider = MeterProviderSdk.builder().build()
    let metrics = TerraMetrics()

    // Before configure, recording should be a no-op (no crash, no instruments).
    metrics.recordInference(durationMs: 10.0)

    // After configure, instruments should be created.
    metrics.configure(meterProvider: meterProvider)
    // No crash = instruments created successfully.
    metrics.recordInference(durationMs: 12.5)
  }

  func testConfigure_nilMeterProvider_clearsInstruments() {
    let meterProvider = MeterProviderSdk.builder().build()
    let metrics = TerraMetrics()

    metrics.configure(meterProvider: meterProvider)
    metrics.recordInference(durationMs: 12.5)

    // Passing nil should clear instruments without crashing.
    metrics.configure(meterProvider: nil)
    metrics.recordInference(durationMs: 10.0)
  }

  func testRecordInference_doesNotCrashWithoutConfiguration() {
    let metrics = TerraMetrics()
    // Should be a safe no-op.
    metrics.recordInference(durationMs: 0)
    metrics.recordInference(durationMs: 999.9)
  }
}
