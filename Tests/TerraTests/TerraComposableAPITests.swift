import Testing
@testable import TerraCore

@Suite("Composable API", .serialized)
struct TerraComposableAPITests {
  @Test("Factory methods return a uniform call type")
  func factoryMethodsReturnUniformCallType() {
    let calls: [Terra.Operation] = [
      Terra.infer(Terra.ModelID("model")),
      Terra.stream(Terra.ModelID("model")),
      Terra.embed(Terra.ModelID("model")),
      Terra.agent("planner"),
      Terra.tool("search", callID: Terra.ToolCallID("call-1")),
      Terra.safety("toxicity"),
    ]
    #expect(calls.count == 6)
  }

  @Test("Uniform call type supports collection transforms")
  func uniformCallTypeSupportsCollectionTransforms() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let transformedCalls: [Terra.Operation] = [
      Terra.infer(Terra.ModelID("model-a"), prompt: "hello"),
      Terra.stream(Terra.ModelID("model-b"), prompt: "world"),
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
      .infer(Terra.ModelID("local/composable"), prompt: "hello")
      .attr(.init("terra.custom.string"), "value")
      .attr(.init("terra.custom.int"), 7)
      .attr(.init("terra.custom.double"), 0.5)
      .attr(.init("terra.custom.bool"), true)
      .run { trace in
        trace.attr(.init("terra.trace.string"), "trace-value")
        trace.tokens(input: 3, output: 4)
        trace.responseModel(Terra.ModelID("trace-model"))
        return "ok"
      }

    #expect(value == "ok")

    let span = try #require(support.finishedSpans().first(where: { $0.name == Terra.SpanNames.inference }))
    #expect(span.attributes["terra.custom.string"]?.description == "value")
    #expect(span.attributes["terra.custom.int"]?.description == "7")
    #expect(span.attributes["terra.custom.double"]?.description == "0.5")
    #expect(span.attributes["terra.custom.bool"]?.description == "true")
    #expect(span.attributes["terra.trace.string"]?.description == "trace-value")
    #expect(span.attributes[Terra.Keys.GenAI.responseModel]?.description == "trace-model")
    #expect(span.attributes[Terra.Keys.GenAI.usageInputTokens]?.description == "3")
    #expect(span.attributes[Terra.Keys.GenAI.usageOutputTokens]?.description == "4")
  }

  @Test("Call metadata builder supports conditionals and loops")
  func callMetadataBuilderSupportsConditionalsAndLoops() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let includeFlag = true
    let phases = ["prepare", "dispatch"]

    _ = try await Terra
      .infer(Terra.ModelID("builder/model"), prompt: "hello")
      .metadata {
        Terra.attr(.init("builder.attr.base"), "base")
        if includeFlag {
          Terra.attr(.init("builder.attr.conditional"), 1)
        }
        for phase in phases {
          Terra.event("builder.event.\(phase)")
        }
      }
      .run { "ok" }

    let span = try #require(support.finishedSpans().first(where: { $0.name == Terra.SpanNames.inference }))
    #expect(span.attributes["builder.attr.base"]?.description == "base")
    #expect(span.attributes["builder.attr.conditional"]?.description == "1")
    #expect(span.events.map(\.name) == ["builder.event.prepare", "builder.event.dispatch"])
  }

  @Test("Trace metadata builder preserves ordering")
  func traceMetadataBuilderPreservesOrdering() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    _ = try await Terra
      .infer(Terra.ModelID("builder/model"), prompt: "hello")
      .run { trace in
        trace.metadata {
          Terra.event("trace.event.1")
          Terra.attr(.init("trace.attr.1"), "v1")
          Terra.event("trace.event.2")
        }
        return "ok"
      }

    let span = try #require(support.finishedSpans().first(where: { $0.name == Terra.SpanNames.inference }))
    #expect(span.events.map(\.name) == ["trace.event.1", "trace.event.2"])
    #expect(span.attributes["trace.attr.1"]?.description == "v1")
  }

  @Test("Metadata builder empty closures are no-op")
  func metadataBuilderEmptyClosuresAreNoOp() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    _ = try await Terra
      .infer(Terra.ModelID("builder/model"), prompt: "hello")
      .metadata { }
      .run { trace in
        trace.metadata { }
        return "ok"
      }

    let span = try #require(support.finishedSpans().first(where: { $0.name == Terra.SpanNames.inference }))
    #expect(span.attributes["builder.attr.base"] == nil)
    #expect(span.events.isEmpty)
  }
}
