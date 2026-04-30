import Foundation
import InMemoryExporter
import OpenTelemetryApi
@testable import OpenTelemetrySdk
@testable import TerraTraceKit
import Testing

/// P1-5 — status descriptions, event names, and link attributes must be routed
/// through the redaction predicate before they can be displayed.
@Suite("SpanDetailViewModel privacy redaction (P1-5)", .serialized)
struct SpanDetailPrivacyTests {
  // MARK: - Status description redaction

  @Test("Content-bearing status descriptions are redacted in SpanDetailViewModel")
  @MainActor
  func testSpanDetailRedactsStatusDescriptionWhenContentBearing() throws {
    let span = makePrivacyFixtureSpan(
      status: .error(description: "User asked the assistant to summarize their personal email."),
      attributes: [:]
    )

    let model = SpanDetailViewModel()
    model.select(span: span)

    let displayed = try #require(model.displayedStatusDescription)
    #expect(displayed == TelemetryPrivacy.redactedValue)
    #expect(!displayed.contains("personal"))
    #expect(!displayed.contains("email"))
  }

  @Test("Short error codes survive redaction")
  @MainActor
  func testSpanDetailKeepsShortStatusCodes() throws {
    let span = makePrivacyFixtureSpan(
      status: .error(description: "ECONNRESET"),
      attributes: [:]
    )

    let model = SpanDetailViewModel()
    model.select(span: span)

    #expect(model.displayedStatusDescription == "ECONNRESET")
  }

  @Test("Empty status messages do not surface a description")
  @MainActor
  func testSpanDetailEmptyStatusDescription() throws {
    let span = makePrivacyFixtureSpan(status: .ok, attributes: [:])

    let model = SpanDetailViewModel()
    model.select(span: span)

    #expect(model.displayedStatusDescription == nil)
  }

  // MARK: - Event-name redaction

  @Test("Content-bearing event names are redacted")
  @MainActor
  func testSpanDetailRedactsContentBearingEventNames() throws {
    let span = makePrivacyFixtureSpanWithEvents(events: [
      ("terra.first_token", [:]),
      ("user wrote: hello model — please summarize", [:]),
    ])

    let model = SpanDetailViewModel()
    model.select(span: span)

    let names = model.eventItems.map(\.name)
    #expect(names.contains("terra.first_token"))
    #expect(!names.contains { $0.contains("hello model") })
    #expect(names.contains(TelemetryPrivacy.redactedValue))
  }

  @Test("Known Terra event names pass through unchanged")
  @MainActor
  func testSpanDetailKeepsKnownTerraEventNames() throws {
    let span = makePrivacyFixtureSpanWithEvents(events: [
      ("terra.first_token", [:]),
      ("chunk.stream", [:]),
      ("terra.parent.explicit_ended", [:]),
      ("terra.recommendation", [:]),
      ("terra.anomaly.thermal", [:]),
      ("terra.policy.violation", [:]),
    ])

    let model = SpanDetailViewModel()
    model.select(span: span)

    let names = Set(model.eventItems.map(\.name))
    #expect(names.contains("terra.first_token"))
    #expect(names.contains("chunk.stream"))
    #expect(names.contains("terra.parent.explicit_ended"))
    #expect(names.contains("terra.recommendation"))
    #expect(names.contains("terra.anomaly.thermal"))
    #expect(names.contains("terra.policy.violation"))
    #expect(!names.contains(TelemetryPrivacy.redactedValue))
  }

  // MARK: - Link-attribute redaction (P1-5 forward-compat)

  @Test("Link attributes are routed through the privacy redactor when surfaced")
  @MainActor
  func testSpanLinkAttributesPassThroughRedactionWhenSurfaced() throws {
    let traceId = TraceId()
    let spanId = SpanId.random()
    let linkContext = SpanContext.create(
      traceId: traceId,
      spanId: spanId,
      traceFlags: TraceFlags(),
      traceState: TraceState()
    )
    let link = SpanData.Link(
      context: linkContext,
      attributes: [
        "gen_ai.prompt.content": OpenTelemetryApi.AttributeValue.string("user typed secret"),
        "terra.link.kind": OpenTelemetryApi.AttributeValue.string("session-parent"),
      ]
    )

    let exporter = InMemoryExporter()
    let provider = TracerProviderSdk()
    provider.addSpanProcessor(SimpleSpanProcessor(spanExporter: exporter))
    let tracer = provider.get(instrumentationName: "SpanDetailPrivacyTests")
    let span = tracer.spanBuilder(spanName: "linked").startSpan()
    span.end()
    provider.forceFlush()
    var spanData = exporter.getFinishedSpanItems()[0]
    spanData = spanData.settingLinks([link])

    let model = SpanDetailViewModel()
    model.select(span: spanData)

    let item = try #require(model.linkItems.first)
    let attributesByKey = Dictionary(uniqueKeysWithValues: item.attributes)
    #expect(attributesByKey["gen_ai.prompt.content"] == TelemetryPrivacy.redactedValue)
    #expect(attributesByKey["terra.link.kind"] == "session-parent")
  }
}

// MARK: - Helpers

@MainActor
private func makePrivacyFixtureSpan(
  status: Status,
  attributes: [String: OpenTelemetryApi.AttributeValue]
) -> SpanData {
  let exporter = InMemoryExporter()
  let provider = TracerProviderSdk()
  provider.addSpanProcessor(SimpleSpanProcessor(spanExporter: exporter))
  let tracer = provider.get(instrumentationName: "SpanDetailPrivacyTests")
  let span = tracer.spanBuilder(spanName: "privacy-status").startSpan()
  span.setAttributes(attributes)
  span.status = status
  span.end()
  provider.forceFlush()
  return exporter.getFinishedSpanItems()[0]
}

@MainActor
private func makePrivacyFixtureSpanWithEvents(
  events: [(String, [String: OpenTelemetryApi.AttributeValue])]
) -> SpanData {
  let exporter = InMemoryExporter()
  let provider = TracerProviderSdk()
  provider.addSpanProcessor(SimpleSpanProcessor(spanExporter: exporter))
  let tracer = provider.get(instrumentationName: "SpanDetailPrivacyTests")
  let span = tracer.spanBuilder(spanName: "privacy-events").startSpan()
  for (name, attrs) in events {
    span.addEvent(name: name, attributes: attrs)
  }
  span.end()
  provider.forceFlush()
  return exporter.getFinishedSpanItems()[0]
}
