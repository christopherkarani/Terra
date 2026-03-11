import XCTest
import InMemoryExporter
import OpenTelemetryApi
import OpenTelemetrySdk

@testable import TerraCore

final class TerraRuntimeInstallTests: XCTestCase {
  private var support: TerraTestSupport!

  override func setUp() {
    super.setUp()
    support = TerraTestSupport()
  }

  override func tearDown() {
    support.reset()
    super.tearDown()
  }

  func testInstallClearsTracerProviderOverrideWhenUnset() async {
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let firstRequest = Terra.InferenceRequest(model: "model-a", prompt: "hello")
    await Terra.withInferenceSpan(firstRequest) { _ in }
    XCTAssertEqual(support.finishedSpans().count, 1)

    let fallbackExporter = InMemoryExporter()
    let fallbackProvider = TracerProviderSdk()
    fallbackProvider.addSpanProcessor(SimpleSpanProcessor(spanExporter: fallbackExporter))
    OpenTelemetry.registerTracerProvider(tracerProvider: fallbackProvider)

    Terra.install(.init(registerProvidersAsGlobal: false))

    let secondRequest = Terra.InferenceRequest(model: "model-b", prompt: "world")
    await Terra.withInferenceSpan(secondRequest) { _ in }
    fallbackProvider.forceFlush()

    XCTAssertEqual(
      support.finishedSpans().count,
      1,
      "Second install without tracerProvider should clear override instead of reusing stale provider."
    )
    XCTAssertEqual(
      fallbackExporter.getFinishedSpanItems().count,
      1,
      "After clearing override, spans should be emitted to the current global tracer provider."
    )
  }
}
