import Foundation
import OpenTelemetryApi
@testable import OpenTelemetrySdk
import TerraTraceKit
import Testing
@testable import TraceMacAppUI

private func makeDashboardTestSpan(
  traceId: TraceId,
  start: Date,
  end: Date
) -> SpanData {
  SpanData(
    traceId: traceId,
    spanId: SpanId(),
    traceFlags: TraceFlags(),
    traceState: TraceState(),
    resource: Resource(),
    instrumentationScope: InstrumentationScopeInfo(),
    name: "terra.inference",
    kind: .internal,
    startTime: start,
    endTime: end,
    hasRemoteParent: false,
    hasEnded: true
  )
}

@Suite("DashboardViewModel parity")
struct DashboardViewModelTests {
  @Test("Dashboard hardware count includes both name-based and attribute-based signals")
  func dashboardHardwareCountUsesParitySignals() throws {
    let traceId = TraceId()
    var span = makeDashboardTestSpan(
      traceId: traceId,
      start: Date(timeIntervalSince1970: 10),
      end: Date(timeIntervalSince1970: 12)
    )

    span = span.settingEvents([
      SpanData.Event(name: "terra.hw.snapshot", timestamp: .now, attributes: [:]),
      SpanData.Event(name: "terra.process.telemetry", timestamp: .now, attributes: [:]),
      SpanData.Event(
        name: "provider.event",
        timestamp: .now,
        attributes: ["terra.hw.memory_pressure": .string("warning")]
      ),
      SpanData.Event(
        name: "provider.event",
        timestamp: .now,
        attributes: ["terra.process.thermal_state": .string("nominal")]
      ),
    ])

    let trace = try Trace(fileName: "1000", spans: [span])
    let metrics = DashboardViewModel.compute(from: [trace])
    #expect(metrics.hardwareTelemetryEventCount == 4)
  }

  @Test("Dashboard recommendation and anomaly counts include attribute-driven events")
  func dashboardRecommendationAndAnomalyCountsUseParitySignals() throws {
    let traceId = TraceId()
    var span = makeDashboardTestSpan(
      traceId: traceId,
      start: Date(timeIntervalSince1970: 20),
      end: Date(timeIntervalSince1970: 22)
    )

    span = span.settingEvents([
      SpanData.Event(
        name: "provider.event",
        timestamp: .now,
        attributes: ["terra.recommendation.kind": .string("thermal_slowdown")]
      ),
      SpanData.Event(
        name: "provider.event",
        timestamp: .now,
        attributes: ["terra.anomaly.kind": .string("stalled_token")]
      ),
    ])

    let trace = try Trace(fileName: "2000", spans: [span])
    let metrics = DashboardViewModel.compute(from: [trace])
    #expect(metrics.recommendationCount == 1)
    #expect(metrics.anomalyCount == 1)
  }
}
