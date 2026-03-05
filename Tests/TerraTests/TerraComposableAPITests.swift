import Testing
@testable import TerraCore

@Suite("Composable API", .serialized)
struct TerraComposableAPITests {
  @Test("Factory methods return a uniform call type")
  func factoryMethodsReturnUniformCallType() {
    let calls: [Terra.Call] = [
      Terra.infer("model"),
      Terra.stream("model"),
      Terra.embed("model"),
      Terra.agent("planner"),
      Terra.tool("search", callID: "call-1"),
      Terra.safety("toxicity"),
    ]
    #expect(calls.count == 6)
  }

  @Test("Uniform call type supports collection transforms")
  func uniformCallTypeSupportsCollectionTransforms() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let transformedCalls: [Terra.Call] = [
      Terra.infer("model-a", prompt: "hello"),
      Terra.stream("model-b", prompt: "world"),
    ]
      .enumerated()
      .map { index, call in
        call
          .capture(index == 0 ? .includeContent : .default)
          .attr(.init("terra.collection.index"), index)
      }

    for call in transformedCalls {
      _ = try await call.run { "ok" }
    }

    let spans = support.finishedSpans().filter { span in
      Terra.SpanNames.isTerraSpanName(span.name)
        && span.attributes["terra.collection.index"] != nil
    }
    #expect(spans.count == 2)
    let indices = Set(spans.compactMap { $0.attributes["terra.collection.index"]?.description })
    #expect(indices == ["0", "1"])
  }

  @Test("Scalar-based attr API records call and trace attributes")
  func scalarAttrRecordsAttributes() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let value = await Terra
      .infer("local/composable", prompt: "hello")
      .attr(.init("terra.custom.string"), "value")
      .attr(.init("terra.custom.int"), 7)
      .attr(.init("terra.custom.double"), 0.5)
      .attr(.init("terra.custom.bool"), true)
      .run { trace in
        trace.attr(.init("terra.trace.string"), "trace-value")
        trace.tokens(input: 3, output: 4)
        return "ok"
      }

    #expect(value == "ok")

    let span = try #require(support.finishedSpans().first(where: { $0.name == Terra.SpanNames.inference }))
    #expect(span.attributes["terra.custom.string"]?.description == "value")
    #expect(span.attributes["terra.custom.int"]?.description == "7")
    #expect(span.attributes["terra.custom.double"]?.description == "0.5")
    #expect(span.attributes["terra.custom.bool"]?.description == "true")
    #expect(span.attributes["terra.trace.string"]?.description == "trace-value")
    #expect(span.attributes[Terra.Keys.GenAI.usageInputTokens]?.description == "3")
    #expect(span.attributes[Terra.Keys.GenAI.usageOutputTokens]?.description == "4")
  }
}
