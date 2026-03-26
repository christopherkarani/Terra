import Foundation

private actor _PlaygroundEventLog {
  private var events: [String] = []

  func append(_ event: String) {
    events.append(event)
  }

  func snapshot() -> [String] {
    events
  }
}

extension Terra {
  /// A lightweight local runner for guided Terra scenarios.
  public struct Playground: Sendable, Hashable {
    /// A runnable scenario exposed by the Terra playground.
    public struct Scenario: Sendable, Hashable {
      public let id: String
      public let title: String
      public let summary: String
      public let entryPoint: String

      public init(id: String, title: String, summary: String, entryPoint: String) {
        self.id = id
        self.title = title
        self.summary = summary
        self.entryPoint = entryPoint
      }
    }

    /// The result of running a guided playground scenario.
    public struct Result: Sendable, Hashable {
      public let scenario: Scenario
      public let summary: String
      public let recordedEvents: [String]
      public let spanTree: String?
      public let recommendedNextSteps: [String]

      public init(
        scenario: Scenario,
        summary: String,
        recordedEvents: [String],
        spanTree: String?,
        recommendedNextSteps: [String]
      ) {
        self.scenario = scenario
        self.summary = summary
        self.recordedEvents = recordedEvents
        self.spanTree = spanTree
        self.recommendedNextSteps = recommendedNextSteps
      }
    }

    public init() {}

    public func scenarios() -> [Scenario] {
      Terra._playgroundScenarios
    }

    public func run(_ id: String) async throws -> Result {
      try await Terra._runPlaygroundScenario(id)
    }
  }

  /// Returns Terra's guided local playground runner.
  public static func playground() -> Playground {
    Playground()
  }
}

private extension Terra {
  static var _playgroundScenarios: [Playground.Scenario] {
    [
      .init(
        id: "workflow-basic",
        title: "Workflow Basic",
        summary: "Runs the canonical `Terra.workflow` root and records root-span annotations.",
        entryPoint: "Terra.workflow(name:id:_:)"
      ),
      .init(
        id: "workflow-messages",
        title: "Workflow Messages",
        summary: "Runs the buffered transcript workflow through `Terra.workflow(messages:)`.",
        entryPoint: "Terra.workflow(name:id:messages:_:)"
      ),
      .init(
        id: "workflow-tools",
        title: "Workflow Tools",
        summary: "Runs a multi-step workflow with a checkpoint and a child tool call.",
        entryPoint: "Terra.workflow(name:id:_:)"
      ),
      .init(
        id: "stream-basic",
        title: "Stream Basic",
        summary: "Runs a traced streaming helper that records first-token and chunk telemetry.",
        entryPoint: "Terra.stream(_:...).run"
      ),
      .init(
        id: "manual-parent",
        title: "Manual Parent",
        summary: "Runs an explicit-lifecycle parent span and binds a child tool operation under it.",
        entryPoint: "Terra.startSpan(name:id:attributes:)"
      ),
      .init(
        id: "diagnostics",
        title: "Diagnostics",
        summary: "Runs Terra's discovery and diagnostics path without requiring a full app integration.",
        entryPoint: "Terra.help(), Terra.diagnose(), Terra.ask(_:)"
      ),
    ]
  }

  static func _runPlaygroundScenario(_ id: String) async throws -> Playground.Result {
    guard let scenario = _playgroundScenarios.first(where: { $0.id == id }) else {
      throw TerraError.invalidOperation(
        reason: "Unknown Terra playground scenario: \(id)",
        correctAPI: #"Use `Terra.playground().scenarios()` to inspect the available scenario identifiers."#,
        example: """
        let scenarios = Terra.playground().scenarios()
        print(scenarios.map(\\.id))
        """
      )
    }

    switch id {
    case "workflow-basic":
      return try await _runWorkflowBasicScenario(scenario)
    case "workflow-messages":
      return try await _runWorkflowMessagesScenario(scenario)
    case "workflow-tools":
      return try await _runWorkflowToolsScenario(scenario)
    case "stream-basic":
      return try await _runStreamBasicScenario(scenario)
    case "manual-parent":
      return try await _runManualParentScenario(scenario)
    case "diagnostics":
      return _runDiagnosticsScenario(scenario)
    default:
      throw TerraError.invalidOperation(
        reason: "Terra playground scenario dispatch was incomplete for \(id).",
        correctAPI: "Use Terra.playground().scenarios() to inspect the supported scenarios."
      )
    }
  }

  static func _runWorkflowBasicScenario(_ scenario: Playground.Scenario) async throws -> Playground.Result {
    let log = _PlaygroundEventLog()
    let spanTree = try await Terra.workflow(name: "playground.workflow", id: scenario.id) { span in
      await log.append("workflow.start")
      span.event("workflow.start")
      span.tokens(input: 8, output: 13)
      span.responseModel("playground-model")
      let tree = Terra.visualize(Terra.activeSpans())
      await log.append("workflow.complete")
      span.event("workflow.complete")
      return tree
    }
    let recordedEvents = await log.snapshot()

    return .init(
      scenario: scenario,
      summary: "Executed the canonical Terra.workflow root with events, token counts, and a response-model annotation.",
      recordedEvents: recordedEvents,
      spanTree: spanTree,
      recommendedNextSteps: [
        "Use Terra.examples() to inspect more workflow-first snippets.",
        #"Use Terra.ask("workflow with transcript") if you need buffered messages."#,
      ]
    )
  }

  static func _runWorkflowMessagesScenario(_ scenario: Playground.Scenario) async throws -> Playground.Result {
    var messages = [ChatMessage(role: "user", content: "Plan the fix.")]
    let log = _PlaygroundEventLog()
    let spanTree = try await Terra.workflow(name: "playground.workflow.messages", id: scenario.id, messages: &messages) { workflow, transcript in
      await log.append("workflow.start")
      workflow.checkpoint("planning")
      await transcript.append(.init(role: "assistant", content: "Draft plan"))
      _ = await workflow.tool("search", callId: "playground-call-1") { trace in
        await log.append("tool.search")
        trace.event("tool.search")
        return "docs"
      }
      return Terra.visualize(Terra.activeSpans())
    }
    let recordedEvents = await log.snapshot()

    return .init(
      scenario: scenario,
      summary: "Executed the buffered transcript workflow. The caller transcript now contains \(messages.count) messages.",
      recordedEvents: recordedEvents,
      spanTree: spanTree,
      recommendedNextSteps: [
        "Use Terra.guides() and look for Mutable Transcript Workflow.",
        "Await detached work before returning if later transcript mutations must be written back.",
      ]
    )
  }

  static func _runWorkflowToolsScenario(_ scenario: Playground.Scenario) async throws -> Playground.Result {
    let log = _PlaygroundEventLog()
    let spanTree = try await Terra.workflow(name: "playground.workflow.tools", id: scenario.id) { workflow in
      workflow.checkpoint("planning")
      await log.append("checkpoint.planning")
      _ = await workflow.tool("search", callId: "playground-call-2") { trace in
        await log.append("tool.search")
        trace.event("tool.search")
        return "docs"
      }
      return Terra.visualize(Terra.activeSpans())
    }
    let recordedEvents = await log.snapshot()

    return .init(
      scenario: scenario,
      summary: "Executed a multi-step workflow with one root span and a child tool call.",
      recordedEvents: recordedEvents,
      spanTree: spanTree,
      recommendedNextSteps: [
        #"Use Terra.ask("workflow with tools") for the recommended root pattern."#,
        "Use Terra.examples() to inspect additional workflow patterns.",
      ]
    )
  }

  static func _runStreamBasicScenario(_ scenario: Playground.Scenario) async throws -> Playground.Result {
    let log = _PlaygroundEventLog()
    let spanTree = try await Terra.workflow(name: "playground.stream", id: scenario.id) { span in
      _ = await Terra.stream("playground-model", prompt: "Explain").under(span).run { trace in
        await log.append("stream.first_token")
        trace.firstToken()
        await log.append("stream.chunk")
        trace.chunk(6)
        trace.outputTokens(18)
        return "ok"
      }
      return Terra.visualize(Terra.activeSpans())
    }
    let recordedEvents = await log.snapshot()

    return .init(
      scenario: scenario,
      summary: "Executed a streaming helper under a workflow root and recorded first-token plus chunk telemetry.",
      recordedEvents: recordedEvents,
      spanTree: spanTree,
      recommendedNextSteps: [
        "Use Terra.guides() and look for Streaming Token Telemetry.",
        "Keep a wider root span when later tool work must stay correlated to the same response.",
      ]
    )
  }

  static func _runManualParentScenario(_ scenario: Playground.Scenario) async throws -> Playground.Result {
    let parent = Terra.startSpan(name: "playground.manual", id: scenario.id)
    let log = _PlaygroundEventLog()
    await log.append("manual.start")
    parent.event("manual.start")
    let spanTree = Terra.visualize(Terra.activeSpans())
    _ = await Terra.tool("search", callId: "playground-call-3").under(parent).run { trace in
      await log.append("tool.search")
      trace.event("tool.search")
      return "ok"
    }
    await log.append("manual.complete")
    parent.event("manual.complete")
    parent.end()
    let recordedEvents = await log.snapshot()

    return .init(
      scenario: scenario,
      summary: "Executed an explicit-lifecycle parent span with a bound child tool operation.",
      recordedEvents: recordedEvents,
      spanTree: spanTree,
      recommendedNextSteps: [
        "Prefer Terra.workflow for one-shot workflows and reserve startSpan for truly explicit lifecycle needs.",
        "Use Terra.help() if you need the full start-here map.",
      ]
    )
  }

  static func _runDiagnosticsScenario(_ scenario: Playground.Scenario) -> Playground.Result {
    let report = Terra.diagnose()
    return .init(
      scenario: scenario,
      summary: "Printed Terra's start-here map and ran local diagnostics with \(report.issues.count) issues and \(report.suggestions.count) suggestions.",
      recordedEvents: [],
      spanTree: nil,
      recommendedNextSteps: [
        "Print Terra.help() for the canonical API map.",
        #"Use Terra.ask("quickstart and diagnose setup") for targeted onboarding guidance."#,
      ]
    )
  }
}
