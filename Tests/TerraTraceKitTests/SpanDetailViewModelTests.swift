import XCTest
import InMemoryExporter
import OpenTelemetryApi
import OpenTelemetrySdk
@testable import TerraTraceKit

final class SpanDetailViewModelTests: XCTestCase {
  func testSelectCategorizesExtendedTerraEventsAndAttributes() throws {
    let exporter = InMemoryExporter()
    let tracerProvider = TracerProviderSdk()
    tracerProvider.addSpanProcessor(SimpleSpanProcessor(spanExporter: exporter))
    let tracer = tracerProvider.get(instrumentationName: "SpanDetailViewModelTests")

    let span = tracer.spanBuilder(spanName: "terra.inference").startSpan()
    span.setAttribute(key: "terra.runtime.confidence", value: .double(0.91))
    span.setAttribute(key: "terra.control_loop.mode", value: .string("closed_loop"))
    span.setAttribute(key: "terra.availability", value: .string("payload_unavailable"))

    span.addEvent(
      name: "terra.recommendation",
      attributes: [
        "terra.recommendation.id": .string("rec-777"),
        "terra.recommendation.confidence": .double(0.88),
      ]
    )
    span.addEvent(
      name: "terra.anomaly.stalled_token",
      attributes: [
        "terra.anomaly.baseline_key": .string("runtime:model"),
        "terra.anomaly.score": .double(0.72),
      ]
    )
    span.addEvent(
      name: "terra.policy.audit",
      attributes: [
        "terra.policy.reason": .string("runtime_not_allowed"),
      ]
    )
    span.addEvent(
      name: "terra.token.lifecycle",
      attributes: [
        "terra.token.stage": .string("decode"),
        "terra.token.index": .int(4),
      ]
    )
    span.end()

    tracerProvider.forceFlush()
    let spanData = try XCTUnwrap(exporter.getFinishedSpanItems().first)

    let viewModel = SpanDetailViewModel()
    viewModel.select(span: spanData)

    XCTAssertEqual(viewModel.recommendationEventItems.count, 1)
    XCTAssertEqual(viewModel.anomalyEventItems.count, 1)
    XCTAssertEqual(viewModel.policyEventItems.count, 1)
    XCTAssertEqual(viewModel.lifecycleEventItems.count, 1)

    let runtimeConfidenceItem = viewModel.attributeItems.first { $0.key == "terra.runtime.confidence" }
    XCTAssertNotNil(runtimeConfidenceItem)
    XCTAssertEqual(viewModel.attributeItems.first { $0.key == "terra.control_loop.mode" }?.value, "closed_loop")
    XCTAssertEqual(viewModel.attributeItems.first { $0.key == "terra.availability" }?.value, "payload_unavailable")
  }
}
