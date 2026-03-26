import Foundation
import Testing
@testable import TerraCore

@Suite("Terra DX", .serialized)
struct TerraDXTests {
  @Test("Built-in examples cover the canonical workflows")
  func examplesCoverCanonicalWorkflows() {
    let examples = Terra.examples()
    let guides = Terra.guides()

    #expect(examples.count >= 50)
    #expect(guides.count >= 20)
    #expect(examples.contains { $0.title == "Trace Basic Async Work" })
    #expect(examples.contains { $0.title == "Loop Basic Transcript Update" })
    #expect(examples.contains { $0.title == "Playground Run Trace Scenario" })
    #expect(examples.contains { $0.title == "TraceBuilder Compatibility" })
    #expect(examples.allSatisfy { !$0.code.isEmpty })
    #expect(examples.contains { $0.code.contains("Terra.diagnose()") })
    #expect(examples.contains { $0.code.contains("Terra.playground()") })
    #expect(examples.contains { $0.code.contains("instrumented()") })
    #expect(guides.contains { $0.title.contains("Mutable Transcript") })
    #expect(guides.contains { $0.title.contains("Moving Off TraceBuilder") })
  }

  @Test("Diagnose reports local setup issues with actionable fixes")
  func diagnoseReportsActionableIssues() {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let report = Terra.diagnose()

    #expect(report.issues.contains { $0.code == "MISSING_ENDPOINT" })
    #expect(report.issues.contains { $0.code == "MISSING_PRIVACY_POLICY" })
    #expect(report.suggestions.contains { $0.contains("Terra.help()") })
    #expect(report.suggestions.contains { $0.contains("Terra.ask") })
    #expect(report.suggestions.contains { $0.contains("Terra.examples()") })
    #expect(report.isHealthy)
  }

  @Test("Help output exposes the canonical trace-first progression")
  func helpOutputExposesTraceFirstProgression() {
    let help = Terra.help()

    #expect(help.contains("Terra.trace(name:id:_:)"))
    #expect(help.contains("Terra.loop(name:id:messages:_: )") == false)
    #expect(help.contains("Terra.loop(name:id:messages:_:)" ))
    #expect(help.contains("Terra.agentic(name:id:_:)"))
    #expect(help.contains("Terra.trace(name:)"))
    #expect(help.contains("Compatibility APIs"))
  }

  @Test("Active spans can be visualized as ASCII and JSON")
  func activeSpansCanBeVisualized() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let outputs = try await Terra.trace(name: "root", id: "trace-1") { _ in
      let ascii = Terra.visualize(Terra.activeSpans())
      let json = Terra.visualize(Terra.activeSpans(), format: .json)
      return (ascii, json)
    }

    #expect(outputs.0.contains("root (trace-1)"))
    #expect(outputs.1.contains("\"label\""))
    #expect(outputs.1.contains("root (trace-1)"))
  }

  @Test("Span hooks observe lifecycle and errors")
  func spanHooksObserveLifecycleAndErrors() async throws {
    enum ExpectedFailure: Error { case boom }

    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))
    let log = HookLog()

    Terra.removeHooks()
    Terra.onSpanStart { log.starts.append($0.name) }
    Terra.onSpanEnd { span, duration in
      log.ends.append(span.name)
      log.durations.append(duration)
    }
    Terra.onError { error, span in
      log.errors.append("\(span.name):\(error)")
    }

    await #expect(throws: ExpectedFailure.self) {
      try await Terra.trace(name: "hooked") { span in
        span.recordError(ExpectedFailure.boom)
        throw ExpectedFailure.boom
      }
    }

    Terra.removeHooks()

    #expect(log.starts.contains("hooked"))
    #expect(log.ends.contains("hooked"))
    #expect(log.durations.count == 1)
    #expect(log.errors.contains { $0.contains("hooked") })
  }

  @Test("Instrumented services wrap execution in Terra spans")
  func instrumentedServicesWrapExecutionInTerraSpans() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    struct LocalPlanner: Terra.TerraInstrumentable {
      let terraServiceName = "local-planner"

      func terraExecute(_ input: String) async throws -> String {
        "planned:\(input)"
      }
    }

    let service = LocalPlanner().instrumented()
    let result = try await service.terraExecute("triage")

    #expect(result == "planned:triage")

    let span = try #require(support.finishedSpans().first)
    #expect(span.name == "service.local-planner")
    #expect(span.attributes[Terra.Keys.Terra.autoInstrumented]?.description == "true")
    #expect(span.attributes["terra.service.name"]?.description == "local-planner")
  }

  @Test("TraceBuilder creates nested spans and preserves the root")
  func traceBuilderCreatesNestedSpans() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let builder = Terra.trace(name: "process-request")
      .attribute("request.id", "req-1")
      .event("received")

    try await builder.span("validation") { }
    try await builder.span("inference") { }
    builder.end()

    let spans = support.finishedSpans()
    #expect(spans.contains { $0.name == "process-request" })
    #expect(spans.contains { $0.name == "validation" })
    #expect(spans.contains { $0.name == "inference" })
  }

  @Test("Guidance and invalid operation errors expose recovery suggestions")
  func guidanceErrorsExposeRecoverySuggestions() {
    let guidance = Terra.TerraError.guidance(
      message: "This span handle is no longer active.",
      why: "The span ended before the later tool call tried to mutate it.",
      correctAPI: "Terra.trace(name:id:_:) or Terra.startSpan(name:id:attributes:)",
      example: """
      let span = Terra.startSpan(name: "tool")
      span.end()
      """
    )

    let invalid = Terra.TerraError.invalidOperation(
      reason: "TraceBuilder already ended.",
      correctAPI: "Create a new builder with Terra.trace(name:)",
      example: "let builder = Terra.trace(name: \"request\")"
    )

    let agentic = Terra.TerraError.wrongAPIForAgentic(
      usedAPI: "Terra.stream(...).run",
      suggestedAPI: "Terra.agentic(name:id:_:)",
      why: "The workflow needs one parent span across multiple tool calls.",
      example: "try await Terra.agentic(name: \"planner\") { _ in }"
    )

    #expect(guidance.recoverySuggestion.contains("Terra.help()"))
    #expect(guidance.recoverySuggestion.contains("Terra.examples()"))
    #expect(guidance.message.contains("Example:"))
    #expect(invalid.recoverySuggestion.contains("Terra.help()"))
    #expect(agentic.recoverySuggestion.contains("Terra.ask(\"agent loop\")"))
  }
}

private final class HookLog: @unchecked Sendable {
  private let lock = NSLock()
  private var _starts: [String] = []
  private var _ends: [String] = []
  private var _errors: [String] = []
  private var _durations: [Duration] = []

  var starts: [String] {
    get { lock.withLock { _starts } }
    set { lock.withLock { _starts = newValue } }
  }

  var ends: [String] {
    get { lock.withLock { _ends } }
    set { lock.withLock { _ends = newValue } }
  }

  var errors: [String] {
    get { lock.withLock { _errors } }
    set { lock.withLock { _errors = newValue } }
  }

  var durations: [Duration] {
    get { lock.withLock { _durations } }
    set { lock.withLock { _durations = newValue } }
  }
}

private extension NSLock {
  func withLock<R>(_ body: () throws -> R) rethrows -> R {
    lock()
    defer { unlock() }
    return try body()
  }
}
