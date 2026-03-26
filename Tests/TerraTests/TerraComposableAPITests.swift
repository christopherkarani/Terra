import Testing
@testable import TerraCore

@Suite("Composable API", .serialized)
struct TerraComposableAPITests {
  @Test("Factory methods return a uniform call type")
  func factoryMethodsReturnUniformCallType() {
    let calls: [Terra.Operation] = [
      Terra.infer("model"),
      Terra.stream("model"),
      Terra.embed("model"),
      Terra.agent("planner"),
      Terra.tool("search", callId: "call-1"),
      Terra.safety("toxicity"),
    ]
    #expect(calls.count == 6)
  }

  @Test("Uniform call type supports collection transforms")
  func uniformCallTypeSupportsCollectionTransforms() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let transformedCalls: [Terra.Operation] = [
      Terra.infer("model-a", prompt: "hello"),
      Terra.stream("model-b", prompt: "world"),
    ]
      .enumerated()
      .map { index, call in
        call
          .capture(index == 0 ? .includeContent : .default)
      }

    for (index, call) in transformedCalls.enumerated() {
      _ = await call.run { trace in
        trace.tag("terra.collection.index", index)
        return "ok"
      }
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
      .run { trace in
        trace.tag("terra.custom.string", "value")
        trace.tag("terra.custom.int", 7)
        trace.tag("terra.custom.double", 0.5)
        trace.tag("terra.custom.bool", true)
        trace.tag("terra.trace.string", "trace-value")
        trace.tokens(input: 3, output: 4)
        trace.responseModel("trace-model")
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

    _ = await Terra
      .infer("builder/model", prompt: "hello")
      .run { trace in
        trace.tag("builder.attr.base", "base")
        if includeFlag {
          trace.tag("builder.attr.conditional", 1)
        }
        for phase in phases {
          trace.event("builder.event.\(phase)")
        }
        return "ok"
      }

    let span = try #require(support.finishedSpans().first(where: { $0.name == Terra.SpanNames.inference }))
    #expect(span.attributes["builder.attr.base"]?.description == "base")
    #expect(span.attributes["builder.attr.conditional"]?.description == "1")
    #expect(span.events.map(\.name) == ["builder.event.prepare", "builder.event.dispatch"])
  }

  @Test("Trace metadata builder preserves ordering")
  func traceMetadataBuilderPreservesOrdering() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    _ = await Terra
      .infer("builder/model", prompt: "hello")
      .run { trace in
        trace.event("trace.event.1")
        trace.tag("trace.attr.1", "v1")
        trace.event("trace.event.2")
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

    _ = await Terra
      .infer("builder/model", prompt: "hello")
      .run { _ in
        return "ok"
      }

    let span = try #require(support.finishedSpans().first(where: { $0.name == Terra.SpanNames.inference }))
    #expect(span.attributes["builder.attr.base"] == nil)
    #expect(span.events.isEmpty)
  }

  @Test("Operation under(parent) overrides the ambient Terra parent span")
  func operationUnderOverridesAmbientParent() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    try await Terra.trace(name: "outer") { outer in
      let manual = Terra.startSpan(name: "manual")
      defer { manual.end() }

      _ = try await Terra
        .tool("search", callId: "call-1")
        .under(outer)
        .run { "ok" }
    }

    let spans = support.finishedSpans()
    let outer = try #require(spans.first(where: { $0.name == "outer" }))
    let manual = try #require(spans.first(where: { $0.name == "manual" }))
    let tool = try #require(spans.first(where: { $0.name == Terra.SpanNames.toolExecution }))

    #expect(tool.parentSpanId?.hexString == outer.spanId.hexString)
    #expect(tool.parentSpanId?.hexString != manual.spanId.hexString)
  }
}
