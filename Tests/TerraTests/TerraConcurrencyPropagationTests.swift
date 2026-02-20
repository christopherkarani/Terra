import XCTest

@testable import TerraCore

final class TerraConcurrencyPropagationTests: XCTestCase {
  private var support: TerraTestSupport!

  override func setUp() {
    super.setUp()
    support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))
  }

  override func tearDown() {
    support.reset()
    super.tearDown()
  }

  func testStructuredTask_inheritsParentSpanContext() async throws {
    let request = Terra.InferenceRequest(model: "local/llama-3.2-1b", prompt: "hi")

    await Terra.withInferenceSpan(request) { _ in
      async let child: Void = Terra.withToolExecutionSpan(
        tool: .init(name: "search"),
        call: .init(id: "call-1")
      ) { _ in
        // no-op
      }

      _ = await child
    }

    let spans = support.finishedSpans()
    XCTAssertEqual(spans.count, 2)

    guard
      let parent = spans.first(where: { $0.name == Terra.SpanNames.inference }),
      let child = spans.first(where: { $0.name == Terra.SpanNames.toolExecution })
    else {
      XCTFail("Missing expected spans")
      return
    }

    XCTAssertEqual(child.traceId.hexString, parent.traceId.hexString)
    XCTAssertEqual(child.parentSpanId?.hexString, parent.spanId.hexString)
  }

  func testDetachedTask_doesNotInheritParentSpanContext() async throws {
    let request = Terra.InferenceRequest(model: "local/llama-3.2-1b", prompt: "hi")

    await Terra.withInferenceSpan(request) { _ in
      let task = Task.detached {
        await Terra.withToolExecutionSpan(
          tool: .init(name: "search"),
          call: .init(id: "call-1")
        ) { _ in }
      }
      await task.value
    }

    let spans = support.finishedSpans()
    XCTAssertEqual(spans.count, 2)

    guard
      let parent = spans.first(where: { $0.name == Terra.SpanNames.inference }),
      let detached = spans.first(where: { $0.name == Terra.SpanNames.toolExecution })
    else {
      XCTFail("Missing expected spans")
      return
    }

    XCTAssertNil(detached.parentSpanId)
    XCTAssertNotEqual(detached.traceId.hexString, parent.traceId.hexString)
  }

  func testSequentialSpans_doNotLeakParentContext() async throws {
    let request = Terra.InferenceRequest(model: "local/llama-3.2-1b", prompt: "hi")

    await Terra.withInferenceSpan(request) { _ in }
    await Terra.withToolExecutionSpan(tool: .init(name: "search"), call: .init(id: "call-1")) { _ in }

    let spans = support.finishedSpans()
    XCTAssertEqual(spans.count, 2)

    guard
      let first = spans.first(where: { $0.name == Terra.SpanNames.inference }),
      let second = spans.first(where: { $0.name == Terra.SpanNames.toolExecution })
    else {
      XCTFail("Missing expected spans")
      return
    }

    XCTAssertNil(second.parentSpanId)
    XCTAssertNotEqual(second.traceId.hexString, first.traceId.hexString)
  }
}
