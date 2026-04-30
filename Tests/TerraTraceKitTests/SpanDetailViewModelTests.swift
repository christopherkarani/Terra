import InMemoryExporter
import OpenTelemetryApi
@testable import OpenTelemetrySdk
@testable import TerraTraceKit
import XCTest

final class SpanDetailViewModelTests: XCTestCase {
  @MainActor
  func testSpanDetailRedactsSchemaSensitiveAttributes() throws {
    let span = makeSpanData(attributes: [
      "gen_ai.prompt.content": OpenTelemetryApi.AttributeValue.string("secret prompt"),
      "gen_ai.request.model": OpenTelemetryApi.AttributeValue.string("gpt-test"),
      "terra.prompt.sha256": OpenTelemetryApi.AttributeValue.string("prompt-digest"),
      "terra.safety.subject.sha256": OpenTelemetryApi.AttributeValue.string("safety-digest"),
    ])

    let model = SpanDetailViewModel()
    model.select(span: span)

    let promptItem = try XCTUnwrap(model.attributeItems.first { $0.key == "gen_ai.prompt.content" })
    let modelItem = try XCTUnwrap(model.attributeItems.first { $0.key == "gen_ai.request.model" })
    let promptDigestItem = try XCTUnwrap(model.attributeItems.first { $0.key == "terra.prompt.sha256" })
    let safetyDigestItem = try XCTUnwrap(model.attributeItems.first { $0.key == "terra.safety.subject.sha256" })

    XCTAssertEqual(promptItem.value, "[redacted: privacy-sensitive]")
    XCTAssertEqual(modelItem.value, "gpt-test")
    XCTAssertEqual(promptDigestItem.value, "[redacted: privacy-sensitive]")
    XCTAssertEqual(safetyDigestItem.value, "[redacted: privacy-sensitive]")
  }
}

private func makeSpanData(
  attributes: [String: OpenTelemetryApi.AttributeValue]
) -> SpanData {
  let exporter = InMemoryExporter()
  let provider = TracerProviderSdk()
  provider.addSpanProcessor(SimpleSpanProcessor(spanExporter: exporter))
  let tracer = provider.get(instrumentationName: "SpanDetailViewModelTests")
  let span = tracer.spanBuilder(spanName: "privacy").startSpan()
  span.setAttributes(attributes)
  span.end()
  provider.forceFlush()
  return exporter.getFinishedSpanItems()[0]
}
