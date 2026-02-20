import Foundation
import InMemoryExporter
import OpenTelemetryApi
import OpenTelemetrySdk
@testable import TerraCore
@testable import TerraHTTPInstrument

final class HTTPIntegrationTelemetryHarness {
  static let shared = HTTPIntegrationTelemetryHarness()

  private let lock = NSLock()
  private let exporter: InMemoryExporter
  private let tracerProvider: TracerProviderSdk

  private init() {
    exporter = InMemoryExporter()
    tracerProvider = TracerProviderSdk()
    tracerProvider.addSpanProcessor(SimpleSpanProcessor(spanExporter: exporter))
  }

  func reset(hosts: Set<String>) {
    lock.lock()
    defer { lock.unlock() }

    exporter.reset()
    OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
    Terra.install(.init(tracerProvider: tracerProvider, registerProvidersAsGlobal: false))
    HTTPAIInstrumentation.resetForTesting()
    HTTPAIInstrumentation.install(hosts: hosts)
  }

  func finishedSpans() -> [SpanData] {
    tracerProvider.forceFlush()
    return exporter.getFinishedSpanItems()
  }
}
