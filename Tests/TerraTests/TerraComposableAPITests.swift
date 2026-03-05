import Testing
@testable import TerraCore

@Suite("Composable API", .serialized)
struct TerraComposableAPITests {
  @Test("Factory methods return typed operation markers")
  func typedFactoryReturnMarkers() {
    expectComposableCall(Terra.infer("model"))
    expectComposableCall(Terra.stream("model"))
    expectComposableCall(Terra.embed("model"))
    expectComposableCall(Terra.agent("planner"))
    expectComposableCall(Terra.tool("search", callID: "call-1"))
    expectComposableCall(Terra.safety("toxicity"))
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

private func expectComposableCall<Op: Terra.OperationKind>(_ value: Terra.Call<Op>) { _ = value }
