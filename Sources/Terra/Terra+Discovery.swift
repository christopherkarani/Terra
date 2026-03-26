import Foundation

extension Terra {
  /// Structured metadata describing a Terra capability.
  ///
  /// Use capabilities to discover the SDK surface without reading implementation files.
  /// This is especially useful for coding agents that need to choose the right entry point
  /// from symbol names, examples, and intended usage.
  ///
  /// ```swift
  /// let capabilities = Terra.capabilities()
  /// let tracing = capabilities.first { $0.name == "task_tracing" }
  /// print(tracing?.entryPoint ?? "missing")
  /// ```
  public struct Capability: Sendable, Hashable {
    public let name: String
    public let description: String
    public let example: String
    public let entryPoint: String

    public init(name: String, description: String, example: String, entryPoint: String) {
      self.name = name
      self.description = description
      self.example = example
      self.entryPoint = entryPoint
    }
  }

  /// A copy-paste guide for a common Terra workflow.
  ///
  /// Guides explain why a pattern exists, when to use it, and what code shape Terra expects.
  /// They are intended to replace source-diving for common agentic tracing tasks.
  ///
  /// ```swift
  /// let guide = Terra.guides().first { $0.title.contains("Agent Loops") }
  /// print(guide?.solution ?? "No guide")
  /// ```
  public struct Guide: Sendable, Hashable {
    public let title: String
    public let problem: String
    public let solution: String
    public let codeExample: String

    public init(title: String, problem: String, solution: String, codeExample: String) {
      self.title = title
      self.problem = problem
      self.solution = solution
      self.codeExample = codeExample
    }
  }

  /// A runnable Terra example that coding agents can inspect and adapt directly.
  ///
  /// Examples are designed to answer "show me the right shape" without requiring
  /// source diving or external documentation lookup.
  public struct Example: Sendable, Hashable {
    public let title: String
    public let scenario: String
    public let code: String
    public let complexity: ExampleComplexity

    public init(title: String, scenario: String, code: String, complexity: ExampleComplexity) {
      self.title = title
      self.scenario = scenario
      self.code = code
      self.complexity = complexity
    }
  }

  /// Complexity level for built-in Terra examples.
  public enum ExampleComplexity: String, Sendable, Hashable {
    case beginner
    case intermediate
    case advanced
  }

  /// Deterministic guidance returned from `Terra.ask(_:)`.
  ///
  /// `Guidance` gives a coding agent enough context to choose a Terra API without
  /// reverse-engineering internal files.
  ///
  /// ```swift
  /// let guidance = Terra.ask("agentic workflow")
  /// print(guidance.apiToUse)
  /// print(guidance.codeExample)
  /// ```
  public struct Guidance: Sendable, Hashable {
    public let why: String
    public let apiToUse: String
    public let codeExample: String
    public let commonMistakes: [String]

    public init(
      why: String,
      apiToUse: String,
      codeExample: String,
      commonMistakes: [String]
    ) {
      self.why = why
      self.apiToUse = apiToUse
      self.codeExample = codeExample
      self.commonMistakes = commonMistakes
    }
  }

  /// Returns Terra's discoverable capabilities for coding agents and humans.
  ///
  /// Prefer this over guessing which Terra API to call when integrating a new
  /// workflow. The capability list is intentionally structured so autocomplete,
  /// static analysis, and LLM agents can map tasks to entry points.
  ///
  /// ```swift
  /// for capability in Terra.capabilities() {
  ///   print("\\(capability.name): \\(capability.entryPoint)")
  /// }
  /// ```
  public static func capabilities() -> [Capability] {
    [
      Capability(
        name: "agentic_workflows",
        description: "Trace a multi-step agent loop with one root span, child tool/model operations, and explicit detached-task propagation helpers.",
        example: """
        let result = try await Terra.agentic(name: "planner", id: "issue-42") { agent in
          agent.checkpoint("plan")
          return try await agent.tool("search", callId: "call-1") { "ok" }
        }
        """,
        entryPoint: "Terra.agentic(name:id:_:)"
      ),
      Capability(
        name: "task_tracing",
        description: "Trace a unit of async work with one obvious entry point and automatic lifecycle management.",
        example: """
        let value = try await Terra.trace(name: "inference", id: "issue-42") { span in
          span.event("started")
          return "ok"
        }
        """,
        entryPoint: "Terra.trace(name:id:_:)"
      ),
      Capability(
        name: "explicit_span_lifecycle",
        description: "Create spans that outlive a single closure when tool execution or post-processing happens later.",
        example: """
        let span = Terra.startSpan(name: "tool-call", id: "call-42")
        span.event("queued")
        span.end()
        """,
        entryPoint: "Terra.startSpan(name:id:attributes:)"
      ),
      Capability(
        name: "active_span_inspection",
        description: "Inspect the active Terra span to debug propagation or attach child work to the current context.",
        example: """
        if let span = Terra.currentSpan() {
          print(span.spanId)
        }
        """,
        entryPoint: "Terra.currentSpan()"
      ),
      Capability(
        name: "operation_selection",
        description: "Choose between inference, streaming, and agent tracing based on the shape of the workload.",
        example: """
        let call = Terra.stream("local-mlx-model", prompt: "Explain token throughput")
        """,
        entryPoint: "Terra.infer(_:...), Terra.stream(_:...), Terra.agent(_:...)"
      ),
      Capability(
        name: "tool_call_tracing",
        description: "Trace a tool invocation with a stable call ID that can be correlated across agent loops.",
        example: """
        let result = try await Terra.tool("search", callId: "call-1").run {
          "ok"
        }
        """,
        entryPoint: "Terra.tool(_:callId:type:provider:runtime:)"
      ),
      Capability(
        name: "workflow_discovery",
        description: "Ask Terra how to implement a workflow in plain English without reading internal source.",
        example: """
        let guidance = Terra.ask("How do I trace a tool call that happens after streaming?")
        print(guidance.apiToUse)
        """,
        entryPoint: "Terra.ask(_:)"
      ),
      Capability(
        name: "runnable_examples",
        description: "Inspect built-in runnable examples for the exact Terra pattern to copy into your project.",
        example: """
        let examples = Terra.examples()
        print(examples.first?.title ?? "missing")
        """,
        entryPoint: "Terra.examples()"
      ),
      Capability(
        name: "setup_diagnostics",
        description: "Validate Terra startup and tracing context during development before debugging the wrong layer.",
        example: """
        let report = Terra.diagnose()
        print(report.isHealthy)
        """,
        entryPoint: "Terra.diagnose()"
      ),
    ]
  }

  /// Returns opinionated guides for common Terra workflows.
  ///
  /// Each guide is designed to answer "how do I do X?" with enough context to
  /// avoid trial-and-error. The guides intentionally bias toward the APIs Terra
  /// wants callers and coding agents to prefer.
  ///
  /// ```swift
  /// let guide = Terra.guides().first { $0.title == "Choosing infer vs stream vs agent" }
  /// print(guide?.codeExample ?? "")
  /// ```
  public static func guides() -> [Guide] {
    [
      Guide(
        title: "Choosing infer vs stream vs agent",
        problem: "It is unclear which Terra factory matches a request/response call, a token stream, or a full agent loop.",
        solution: "Use infer for one-shot responses, stream for token-by-token output, and agentic for a traced planner/executor loop with tools or multiple iterations.",
        codeExample: """
        let summary = try await Terra.infer("local-coreml-model", prompt: "Summarize").run { "done" }
        let streamed = try await Terra.stream("local-mlx-model", prompt: "Explain").run { trace in
          trace.firstToken()
          return "done"
        }
        let turn = try await Terra.agentic(name: "planner", id: "turn-1") { agent in
          try await agent.tool("search", callId: "call-1") { "done" }
        }
        """
      ),
      Guide(
        title: "Tracing Tool Calls in Agent Loops",
        problem: "Tool work often happens after the model decides to call a tool, so a closure-scoped span ends too early.",
        solution: "Create an explicit span with Terra.startSpan or wrap the whole async task in Terra.trace so the tool work stays inside an active parent span.",
        codeExample: """
        let toolSpan = Terra.startSpan(name: "tool.search", id: "call-1")
        toolSpan.event("dispatch")
        let value = try await Terra.tool("search", callId: "call-1").run { "ok" }
        toolSpan.event("complete")
        toolSpan.end()
        """
      ),
      Guide(
        title: "Spans That Outlive Closures",
        problem: "A span created inside a `.run {}` closure cannot annotate work that happens later in the agent loop.",
        solution: "Use Terra.startSpan for explicit lifecycle, or Terra.trace when one async task should own the full span lifecycle.",
        codeExample: """
        let result = try await Terra.trace(name: "agent-turn", id: "turn-7") { span in
          span.event("planning")
          return try await Terra.tool("search", callId: "call-7").run { "ok" }
        }
        """
      ),
      Guide(
        title: "Inspecting Active Trace Context",
        problem: "When propagation is unclear, it is hard to tell whether the current task is still inside a Terra span.",
        solution: "Call Terra.currentSpan() or Terra.isTracing() inside the async context that should inherit tracing.",
        codeExample: """
        let value = try await Terra.trace(name: "debug") { _ in
          if let active = Terra.currentSpan() {
            print(active.traceId)
          }
          return "ok"
        }
        """
      ),
      Guide(
        title: "Migrating from typed IDs to strings",
        problem: "Older Terra samples wrapped model names and tool call IDs in lightweight types that added ceremony.",
        solution: "Pass model names and tool call IDs as plain strings. Keep ProviderID and RuntimeID only where Terra metadata remains structured.",
        codeExample: """
        let result = try await Terra.infer("local-foundation-model", prompt: "Hello").run { trace in
          trace.responseModel("local-foundation-model")
          return "ok"
        }
        let tool = try await Terra.tool("search", callId: "call-1").run { "ok" }
        """
      ),
    ]
  }

  /// Returns runnable Terra examples that agents can copy and adapt directly.
  ///
  /// Use this first when you want the "right" Terra pattern for a workflow.
  /// The examples are local-first and intentionally show on-device tracing setups.
  public static func examples() -> [Example] {
    [
      Example(
        title: "Basic Inference Tracing",
        scenario: "I want to trace a single on-device inference call.",
        code: """
        import Terra

        let result = try await Terra
          .infer(
            "local-coreml-model",
            prompt: "Summarize the latest local trace",
            runtime: Terra.RuntimeID("coreml")
          )
          .run { trace in
            trace.event("inference.start")
            trace.responseModel("local-coreml-model")
            trace.tokens(input: 32, output: 12)
            return "summary"
          }
        print(result)
        """,
        complexity: .beginner
      ),
      Example(
        title: "Streaming With Tool Calls",
        scenario: "I want to stream a response and then trace a tool call under the same parent span.",
        code: """
        import Terra

        let answer = try await Terra.trace(name: "agent-turn", id: "turn-1") { span in
          span.event("streaming.begin")
          let draft = try await Terra
            .stream("local-mlx-model", prompt: "Inspect local logs", runtime: Terra.RuntimeID("mlx"))
            .run { trace in
              trace.firstToken()
              trace.chunk(8)
              return "draft"
            }

          let docs = try await Terra.tool("read_trace_file", callId: "tool-1").run { trace in
            trace.event("tool.open")
            return "trace contents"
          }

          span.event("streaming.complete")
          return draft + docs
        }
        print(answer)
        """,
        complexity: .intermediate
      ),
      Example(
        title: "Agentic Loop With Tool Calls",
        scenario: "I want to trace a planner/executor loop with multiple iterations.",
        code: """
        import Terra

        let outcome = try await Terra.agentic(name: "planner-loop", id: "issue-42") { agent in
          for iteration in 1...3 {
            agent.checkpoint("iteration.\\(iteration)")
            _ = try await agent.infer("local-mlx-model", prompt: "plan iteration \\(iteration)") { trace in
              trace.event("plan.iteration")
              return "plan-\\(iteration)"
            }
            _ = try await agent.tool("search", callId: "call-\\(iteration)") { trace in
              trace.event("tool.iteration")
              return "results-\\(iteration)"
            }
          }
          return "done"
        }
        print(outcome)
        """,
        complexity: .advanced
      ),
      Example(
        title: "Nested Spans",
        scenario: "I want to visualize a parent span with nested child work.",
        code: """
        import Terra

        let builder = Terra.trace(name: "process-request")
          .attribute("request.id", "req-7")
          .event("received")

        try await builder.span("validation") {
          try await Task.sleep(for: .milliseconds(10))
        }

        try await builder.span("inference") {
          try await Task.sleep(for: .milliseconds(20))
        }

        print(Terra.visualize(Terra.activeSpans()))
        builder.end()
        """,
        complexity: .intermediate
      ),
      Example(
        title: "Error Handling And Reporting",
        scenario: "I want Terra to record an error and tell me how to fix the pattern.",
        code: """
        import Terra

        enum ModelFailure: Error { case offline }

        do {
          try await Terra.trace(name: "failing-work") { span in
            span.event("before-error")
            throw ModelFailure.offline
          }
        } catch let error as Terra.TerraError {
          print(error.recoverySuggestion)
        } catch {
          print(error)
        }
        """,
        complexity: .beginner
      ),
      Example(
        title: "Diagnose Local Setup",
        scenario: "I want to validate my Terra setup before debugging a workflow.",
        code: """
        import Terra

        let report = Terra.diagnose()
        print(report.isHealthy)
        for issue in report.issues {
          print("\\(issue.code): \\(issue.fix)")
        }
        """,
        complexity: .beginner
      ),
      Example(
        title: "Span Lifecycle Hooks",
        scenario: "I want custom behavior when spans start, end, or fail.",
        code: """
        import Terra

        Terra.onSpanEnd { span, duration in
          if duration > .seconds(1) {
            print("Slow span: \\(span.name)")
          }
        }

        _ = try await Terra.trace(name: "hooked") { _ in "ok" }
        Terra.removeHooks()
        """,
        complexity: .intermediate
      ),
      Example(
        title: "Instrument A Service Wrapper",
        scenario: "I want my service to get Terra spans automatically without rewriting its interface.",
        code: """
        import Terra

        struct LocalPlanner: Terra.TerraInstrumentable {
          let terraServiceName = "local-planner"

          func terraExecute(_ input: String) async throws -> String {
            "planned: \\(input)"
          }
        }

        let service = LocalPlanner().instrumented()
        let result = try await service.terraExecute("triage the trace")
        print(result)
        """,
        complexity: .intermediate
      ),
    ]
  }

  /// Ask Terra how to implement a workflow in plain English.
  ///
  /// `ask(_:)` is deterministic and offline. It does not call a model. Instead,
  /// it maps normalized questions to Terra's built-in capabilities and guides so
  /// coding agents can retrieve the intended pattern directly from the SDK.
  ///
  /// ```swift
  /// let guidance = Terra.ask("agentic workflow")
  /// print(guidance.apiToUse)
  /// ```
  public static func ask(_ question: String) -> Guidance {
    let normalized = question.lowercased()

    if normalized.contains("agentic workflow") || normalized.contains("agent loop") {
      return Guidance(
        why: "Agentic workflows usually include planning, tool calls, and follow-up work that outlive a single model callback. Terra.agentic gives one root span owner and keeps child operations explicit through helper methods.",
        apiToUse: "Use Terra.agentic(name:id:_:), then call agent.infer, agent.stream, agent.tool, and agent.detached when work crosses a detached-task boundary.",
        codeExample: """
        let result = try await Terra.agentic(name: "agent-turn", id: "turn-42") { agent in
          agent.checkpoint("planning")
          let draft = try await agent.infer("local-mlx-model", prompt: "Plan") { "draft" }
          let tool = try await agent.tool("search", callId: "call-42") { "results" }
          return draft + tool
        }
        """,
        commonMistakes: [
          "Using Terra.stream(...).run when later tool work needs the same long-lived parent span.",
          "Creating a tool span without a stable callId.",
          "Using raw Task.detached instead of agent.detached when parent trace linkage matters.",
        ]
      )
    }

    if normalized.contains("tool") && normalized.contains("stream") {
      return Guidance(
        why: "Streaming spans end when the streaming closure returns, so later tool work needs an explicit parent span.",
        apiToUse: "Use Terra.startSpan(name:id:attributes:) or Terra.trace(name:id:_:) around the wider workflow, then trace the tool call with Terra.tool(_:callId:...).",
        codeExample: """
        let span = Terra.startSpan(name: "stream-and-tool", id: "call-1")
        let response = try await Terra.stream("local-foundation-model", prompt: "Explain").run { "done" }
        let tool = try await Terra.tool("search", callId: "call-1").run { "ok" }
        span.end()
        """,
        commonMistakes: [
          "Assuming a `.run {}` span remains active after the closure exits.",
          "Ending the parent span before the tool finishes.",
        ]
      )
    }

    if normalized.contains("trace") || normalized.contains("span") {
      return Guidance(
        why: "Tracing is easiest when one API owns lifecycle and context propagation.",
        apiToUse: "Prefer Terra.trace(name:id:_:) for a full async task. Use Terra.startSpan(name:id:attributes:) only when lifecycle must be explicit.",
        codeExample: """
        let value = try await Terra.trace(name: "work") { span in
          span.event("start")
          return "ok"
        }
        """,
        commonMistakes: [
          "Manually starting a span when Terra.trace would be simpler.",
          "Expecting Terra.currentSpan() to stay non-nil after the traced task ends.",
        ]
      )
    }

    return Guidance(
      why: "Terra ships a built-in discovery catalog so callers can inspect capabilities, runnable examples, and diagnostics instead of guessing API shape.",
      apiToUse: "Start with Terra.examples(), Terra.capabilities(), and Terra.guides(), then use Terra.trace(name:id:_:) as the default tracing entry point.",
      codeExample: """
      let report = Terra.diagnose()
      let examples = Terra.examples()
      let capabilities = Terra.capabilities()
      let guides = Terra.guides()
      let result = try await Terra.trace(name: "work") { _ in "ok" }
      """,
      commonMistakes: [
        "Treating Terra.ask as an LLM call. It is a deterministic lookup.",
        "Skipping Terra.guides() and falling back to internal source inspection.",
      ]
    )
  }
}
