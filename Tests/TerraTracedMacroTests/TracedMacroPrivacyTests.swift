import Testing
@testable import TerraCore
import TerraTracedMacro
import OpenTelemetryApi
import OpenTelemetrySdk
import InMemoryExporter

private struct MacroPrivacyHarness {
  let previousTracerProvider: any TracerProvider
  let spanExporter: InMemoryExporter
  let tracerProvider: TracerProviderSdk

  init(privacy: Terra.Privacy) {
    Terra.lockTestingIsolation()
    previousTracerProvider = OpenTelemetry.instance.tracerProvider
    Terra.resetOpenTelemetryForTesting()
    spanExporter = InMemoryExporter()
    tracerProvider = TracerProviderSdk()
    tracerProvider.addSpanProcessor(SimpleSpanProcessor(spanExporter: spanExporter))
    OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
    Terra.install(.init(
      privacy: privacy,
      tracerProvider: tracerProvider,
      registerProvidersAsGlobal: false
    ))
  }

  func finishedSpans() -> [SpanData] {
    tracerProvider.forceFlush()
    return spanExporter.getFinishedSpanItems()
  }

  func tearDown() {
    Terra.resetOpenTelemetryForTesting()
    OpenTelemetry.registerTracerProvider(tracerProvider: previousTracerProvider)
    Terra.unlockTestingIsolation()
  }
}

private struct MacroPrivacySubject {
  @Traced(model: Terra.ModelID("privacy-model"))
  func generate(prompt: String) async throws -> String {
    return "ok"
  }
}

@Test("Traced macro path respects privacy defaults for prompt capture")
func tracedMacroRespectsPrivacyDefaults() async throws {
  let secret = "macro-secret-prompt"
  let harness = MacroPrivacyHarness(
    privacy: .init(contentPolicy: .optIn, redaction: .hashHMACSHA256)
  )
  defer { harness.tearDown() }

  _ = try await MacroPrivacySubject().generate(prompt: secret)
  let span = try #require(harness.finishedSpans().first)
  #expect(span.attributes[Terra.Keys.Terra.promptLength] == nil)
  #expect(span.attributes[Terra.Keys.Terra.promptHMACSHA256] == nil)
  #expect(span.attributes.values.allSatisfy { !$0.description.contains(secret) })
}
