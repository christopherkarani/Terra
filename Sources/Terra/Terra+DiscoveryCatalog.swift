import Foundation

private extension Terra {
  static func capability(
    _ name: String,
    _ description: String,
    _ example: String,
    _ entryPoint: String,
    preference: Capability.Preference = .primary
  ) -> Capability {
    Capability(
      name: name,
      description: description,
      example: example,
      entryPoint: entryPoint,
      preference: preference
    )
  }

  static func guide(
    _ title: String,
    problem: String,
    solution: String,
    codeExample: String
  ) -> Guide {
    Guide(title: title, problem: problem, solution: solution, codeExample: codeExample)
  }

  static func example(
    _ title: String,
    scenario: String,
    code: String,
    complexity: ExampleComplexity
  ) -> Example {
    Example(title: title, scenario: scenario, code: code, complexity: complexity)
  }
}

extension Terra {
  package static var _capabilityCatalog: [Capability] {
    [
      capability(
        "start_here",
        "Print Terra's start-here tree before integrating a new workflow.",
        #"print(Terra.help())"#,
        "Terra.help()"
      ),
      capability(
        "task_tracing",
        "Trace one async task with automatic lifecycle and a `SpanHandle` root.",
        #"let value = try await Terra.trace(name: "work") { span in span.event("start"); return "ok" }"#,
        "Terra.trace(name:id:_:)"
      ),
      capability(
        "mutable_agent_loops",
        "Trace an agent loop that mutates a chat transcript without capturing `inout` inside a `@Sendable` closure.",
        #"let result = try await Terra.loop(name: "planner", messages: &messages) { loop in await loop.appendMessage(.init(role: "assistant", content: "draft")); return "ok" }"#,
        "Terra.loop(name:id:messages:_:)"
      ),
      capability(
        "agentic_workflows",
        "Trace a multi-step agent workflow with one root span, child operations, and detached-task propagation helpers.",
        #"let result = try await Terra.agentic(name: "planner") { agent in try await agent.tool("search", callId: "call-1") { "ok" } }"#,
        "Terra.agentic(name:id:_:)"
      ),
      capability(
        "explicit_lifecycle",
        "Create spans that outlive a single closure when later work must stay under the same parent.",
        #"let span = Terra.startSpan(name: "tool-call"); span.event("queued"); span.end()"#,
        "Terra.startSpan(name:id:attributes:)"
      ),
      capability(
        "child_operations",
        "Build traced inference, streaming, embedding, tool, and safety child operations under the current or explicit parent span.",
        #"let result = try await Terra.infer("local-model", prompt: "Hi").run { trace in trace.tokens(input: 4, output: 8); return "ok" }"#,
        "Terra.infer(_:...), Terra.stream(_:...), Terra.embed(_:...), Terra.tool(_:...), Terra.safety(_:...)",
        preference: .secondary
      ),
      capability(
        "current_span",
        "Inspect the currently active Terra span inside an async context.",
        #"if let span = Terra.currentSpan() { print(span.traceId) }"#,
        "Terra.currentSpan()",
        preference: .secondary
      ),
      capability(
        "active_span_inspection",
        "Inspect the active Terra span to debug propagation or visualize active work.",
        #"if let span = Terra.currentSpan() { print(span.traceId) }"#,
        "Terra.currentSpan(), Terra.activeSpans(), Terra.visualize(_:)",
        preference: .secondary
      ),
      capability(
        "setup_diagnostics",
        "Validate startup and tracing context before debugging the wrong layer.",
        #"let report = Terra.diagnose()"#,
        "Terra.diagnose()"
      ),
      capability(
        "workflow_discovery",
        "Ask Terra which pattern to use and pull runnable examples or guides without reading implementation files.",
        #"let guidance = Terra.ask("agent loop with mutable messages")"#,
        "Terra.ask(_:), Terra.examples(), Terra.guides()"
      ),
      capability(
        "playground",
        "Run guided local scenarios that exercise the canonical tracing surface.",
        #"let result = try await Terra.playground().run("trace-basic")"#,
        "Terra.playground()",
        preference: .secondary
      ),
      capability(
        "trace_builder_compatibility",
        "Compatibility builder retained for migration only. Prefer `Terra.trace` or `Terra.startSpan` for new code.",
        #"let builder = Terra.trace(name: "request")"#,
        "Terra.trace(name:)",
        preference: .compatibility
      ),
    ]
  }

  package static var _guideCatalog: [Guide] {
    [
      guide(
        "Start Here With quickStart And help",
        problem: "New users need one obvious path into Terra without source-diving.",
        solution: "Start with `Terra.quickStart()`, then print `Terra.help()` and run `Terra.diagnose()` before integrating real model work.",
        codeExample: """
        try await Terra.quickStart()
        print(Terra.help())
        let report = Terra.diagnose()
        """
      ),
      guide(
        "Choosing trace vs loop vs agentic vs startSpan",
        problem: "It is unclear which top-level tracing API matches the workflow shape.",
        solution: "Use `trace` for one async task, `loop` for mutable transcripts, `agentic` for multi-step workflows without transcript mutation, and `startSpan` only when lifecycle must stay explicit beyond a closure.",
        codeExample: """
        let value = try await Terra.trace(name: "request") { _ in "ok" }
        let result = try await Terra.loop(name: "planner", messages: &messages) { _ in "ok" }
        let turn = try await Terra.agentic(name: "planner") { _ in "ok" }
        let span = Terra.startSpan(name: "manual")
        span.end()
        """
      ),
      guide(
        "Choosing infer vs stream vs embed vs tool vs safety",
        problem: "The operation helpers overlap unless the caller understands their telemetry intent.",
        solution: "Use `infer` for one-shot model responses, `stream` for token-by-token output, `embed` for vector generation, `tool` for explicit tool calls, and `safety` for evaluations.",
        codeExample: """
        _ = try await Terra.infer("local-model", prompt: "Summarize").run { "ok" }
        _ = try await Terra.stream("local-model", prompt: "Explain").run { trace in trace.firstToken(); return "ok" }
        _ = try await Terra.embed("local-embedder", inputCount: 4).run { [0.1, 0.2] }
        _ = try await Terra.tool("search", callId: "call-1").run { "ok" }
        _ = try await Terra.safety("prompt_review", subject: "hello").run { "safe" }
        """
      ),
      guide(
        "Tracing Tool Calls After Streaming",
        problem: "Streaming closures end before later tool work starts, so child work loses the intended parent span.",
        solution: "Wrap the whole workflow in `Terra.trace` or use `Terra.startSpan` explicitly, then run the tool under that parent.",
        codeExample: """
        let answer = try await Terra.trace(name: "stream-and-tool") { span in
          _ = try await Terra.stream("local-model", prompt: "Explain").run { "draft" }
          return try await Terra.tool("search", callId: "call-1").under(span).run { "docs" }
        }
        """
      ),
      guide(
        "Spans That Outlive Closures",
        problem: "A closure-scoped span cannot annotate work that happens later in the workflow.",
        solution: "Reach for `Terra.startSpan` only when `Terra.trace` cannot own the whole lifecycle.",
        codeExample: """
        let span = Terra.startSpan(name: "manual-sync")
        span.event("queued")
        defer { span.end() }
        """
      ),
      guide(
        "Mutable Transcript Agent Loops",
        problem: "Agent loops often mutate `[ChatMessage]` with `inout`, which cannot be captured inside `@Sendable` closures.",
        solution: "Use `Terra.loop(messages:)` and mutate the buffered transcript through the `AgentLoopScope` methods.",
        codeExample: """
        var messages = [Terra.ChatMessage(role: "user", content: "Plan the fix.")]
        let result = try await Terra.loop(name: "planner", messages: &messages) { loop in
          await loop.appendMessage(.init(role: "assistant", content: "Draft plan"))
          return "ok"
        }
        """
      ),
      guide(
        "Buffered Transcript Writeback",
        problem: "Users need to know when `loop(messages:)` writes the transcript back to the caller.",
        solution: "`Terra.loop` snapshots the buffer when the root body returns or throws. Await detached work before returning if its transcript mutations must persist.",
        codeExample: """
        try await Terra.loop(name: "planner", messages: &messages) { loop in
          let task = loop.detached { detached in
            await detached.appendMessage(.init(role: "assistant", content: "late"))
          }
          try await task.value
          return "done"
        }
        """
      ),
      guide(
        "Detached Tasks In Agent Workflows",
        problem: "Raw `Task.detached` drops Terra's task-local span context.",
        solution: "Use `SpanHandle.detached`, `AgentHandle.detached`, or `AgentLoopScope.detached` whenever parent trace linkage matters.",
        codeExample: """
        try await Terra.agentic(name: "planner") { agent in
          let task = agent.detached { detached in
            detached.checkpoint("background")
            return "ok"
          }
          return try await task.value
        }
        """
      ),
      guide(
        "Inspecting Active Trace Context",
        problem: "When propagation is unclear, it is hard to tell whether the current task is still inside a Terra span.",
        solution: "Call `Terra.currentSpan()` or `Terra.isTracing()` in the exact async context you want to validate.",
        codeExample: """
        let value = try await Terra.trace(name: "debug") { _ in
          if let span = Terra.currentSpan() {
            print(span.traceId)
          }
          return "ok"
        }
        """
      ),
      guide(
        "Recording Tokens And Response Models",
        problem: "Token and response-model metadata is scattered across tracing styles unless callers know the shared keys.",
        solution: "Use `SpanHandle.tokens` and `SpanHandle.responseModel` for the shared annotation path. `TraceHandle` forwards the same semantics for operation helpers.",
        codeExample: """
        try await Terra.trace(name: "inference") { span in
          span.tokens(input: 12, output: 18)
          span.responseModel("local-model")
          return "ok"
        }
        """
      ),
      guide(
        "Bridging Operation Helpers Under A Manual Span",
        problem: "A composable operation sometimes needs to bind under a parent span chosen outside the `.run` closure.",
        solution: "Create the parent with `trace` or `startSpan`, then attach the operation with `.under(parent)`.",
        codeExample: """
        let parent = Terra.startSpan(name: "sync")
        defer { parent.end() }
        _ = try await Terra.tool("search", callId: "call-1").under(parent).run { "ok" }
        """
      ),
      guide(
        "Privacy And includeContent",
        problem: "Content capture is opt-in per call and still gated by Terra's privacy configuration.",
        solution: "Keep Terra redacted by default, then use `.capture(.includeContent)` or `includeContent` request options only for the narrow workflows that need it.",
        codeExample: """
        _ = try await Terra
          .infer("local-model", prompt: "Hello")
          .capture(.includeContent)
          .run { "ok" }
        """
      ),
      guide(
        "Diagnosing Local Setup",
        problem: "Integration errors are often caused by missing providers or endpoints rather than the tracing call site.",
        solution: "Run `Terra.diagnose()` first and follow the fixes before debugging your workflow code. Use `Terra.help()` if you need the start-here map.",
        codeExample: """
        let report = Terra.diagnose()
        print(report.isHealthy)
        print(report.suggestions.joined(separator: "\\n"))
        """
      ),
      guide(
        "Reading Error Remediation",
        problem: "Terra errors carry structured guidance that is easy to ignore if callers only print the localized description.",
        solution: "When you catch `TerraError`, read `recoverySuggestion` and inspect `context` for the exact API or configuration fix.",
        codeExample: """
        do {
          try await Terra.trace(name: "work") { _ in throw SomeError.failed }
        } catch let error as Terra.TerraError {
          print(error.recoverySuggestion)
          print(error.context)
        }
        """
      ),
      guide(
        "Stable Tool Call IDs",
        problem: "Tool telemetry is hard to correlate across agent steps without a stable `callId`.",
        solution: "Pass the upstream tool identifier into `Terra.tool(..., callId:)` whenever one already exists.",
        codeExample: """
        _ = try await Terra.tool("search", callId: "tool-call-42").run { "ok" }
        """
      ),
      guide(
        "Streaming Token Telemetry",
        problem: "Streaming traces need first-token and chunk metadata to explain user-perceived latency.",
        solution: "Use `TraceHandle.firstToken`, `chunk`, and `outputTokens` inside `Terra.stream(...).run`.",
        codeExample: """
        _ = try await Terra.stream("local-model", prompt: "Explain").run { trace in
          trace.firstToken()
          trace.chunk(8)
          trace.outputTokens(24)
          return "ok"
        }
        """
      ),
      guide(
        "Multi-model Agent Loops",
        problem: "Agent workflows often switch between fast planning models and slower answer models.",
        solution: "Keep one `trace`, `loop`, or `agentic` root span and record each child inference explicitly so the model mix stays visible.",
        codeExample: """
        try await Terra.agentic(name: "planner") { agent in
          _ = try await agent.infer("fast-model", prompt: "Plan") { "plan" }
          return try await agent.infer("accurate-model", prompt: "Answer") { "answer" }
        }
        """
      ),
      guide(
        "Service Instrumentation",
        problem: "A service API should stay stable even when Terra tracing is added.",
        solution: "Conform the service to `TerraInstrumentable` and wrap it with `.instrumented()`.",
        codeExample: """
        struct Planner: Terra.TerraInstrumentable {
          let terraServiceName = "planner"
          func terraExecute(_ input: String) async throws -> String { input }
        }
        let service = Planner().instrumented()
        """
      ),
      guide(
        "Visualizing Active Spans",
        problem: "Terminal-based debugging benefits from a plain-text view of currently active spans.",
        solution: "Use `Terra.activeSpans()` and `Terra.visualize(...)` to inspect hierarchy without dropping into OpenTelemetry APIs.",
        codeExample: """
        let tree = try await Terra.trace(name: "root") { _ in
          Terra.visualize(Terra.activeSpans())
        }
        print(tree)
        """
      ),
      guide(
        "Migrating From Typed IDs To Strings",
        problem: "Older samples wrapped model names and tool-call identifiers in lightweight types that added ceremony.",
        solution: "Pass model names and `callId` values as strings. Keep `ProviderID` and `RuntimeID` where structured metadata still helps.",
        codeExample: """
        _ = try await Terra.infer("local-model", prompt: "Hello").run { "ok" }
        _ = try await Terra.tool("search", callId: "call-1").run { "ok" }
        """
      ),
      guide(
        "Moving Off TraceBuilder",
        problem: "The old builder path looks attractive but hides lifecycle decisions and duplicates the trace mental model.",
        solution: "Prefer `Terra.trace` for one-shot traced work. If you truly need explicit lifecycle, use `Terra.startSpan` directly.",
        codeExample: """
        let value = try await Terra.trace(name: "request") { span in
          span.event("received")
          return "ok"
        }
        """
      ),
      guide(
        "Using The Playground Runner",
        problem: "Teams want a safe way to try Terra patterns locally without wiring them into an app first.",
        solution: "Use `Terra.playground()` to list guided scenarios and run a small local trace workflow.",
        codeExample: """
        let playground = Terra.playground()
        print(playground.scenarios().map(\\.id))
        let result = try await playground.run("trace-basic")
        print(result.summary)
        """
      ),
      guide(
        "Choosing TraceHandle Compatibility",
        problem: "Existing operation helpers still expose `TraceHandle`, which can look like a second primary span type.",
        solution: "Treat `TraceHandle` as an operation-scoped compatibility wrapper. For new root-span code, prefer `SpanHandle` through `Terra.trace`, `Terra.loop`, or `Terra.startSpan`.",
        codeExample: """
        _ = try await Terra.infer("local-model", prompt: "Hello").run { trace in
          trace.event("compat")
          return "ok"
        }
        """
      ),
      guide(
        "Using help And ask Together",
        problem: "New users often know the intent of their workflow but not Terra's vocabulary for it.",
        solution: "Use `help()` to scan the entry points, then `ask(...)` with plain English to retrieve the closest runnable pattern.",
        codeExample: """
        print(Terra.help())
        let guidance = Terra.ask("agent loop with mutable messages")
        print(guidance.apiToUse)
        """
      ),
    ]
  }

  package static var _exampleCatalog: [Example] {
    _baseExamples()
      + _traceExamples()
      + _operationExamples()
      + _loopExamples()
      + _debugExamples()
      + _playgroundExamples()
  }

  package static func _helpTree() -> String {
    let primary = _capabilityCatalog.filter { $0.preference == .primary }
    let secondary = _capabilityCatalog.filter { $0.preference == .secondary }
    let compatibility = _capabilityCatalog.filter { $0.preference == .compatibility }

    func lines(for capabilities: [Capability]) -> String {
      capabilities
        .map { "- \($0.entryPoint): \($0.description)" }
        .joined(separator: "\n")
    }

    return """
    Terra Help

    Start Here
    - try await Terra.quickStart()
    - print(Terra.help())
    - let report = Terra.diagnose()
    - let guidance = Terra.ask("agent loop with mutable messages")

    Primary APIs
    \(lines(for: primary))

    Secondary APIs
    \(lines(for: secondary))

    Compatibility APIs
    \(lines(for: compatibility))

    Discovery Shortcuts
    - Terra.examples(): \(examples().count) runnable snippets
    - Terra.guides(): \(guides().count) copy-paste guides
    - Terra.playground(): guided local scenario runner
    """
  }

  package static func _guidance(for question: String) -> Guidance {
    let normalized = question.lowercased()

    if normalized.contains("message")
      || normalized.contains("transcript")
      || normalized.contains("chat history")
      || normalized.contains("inout")
    {
      return Guidance(
        why: "`inout [ChatMessage]` cannot be captured in a `@Sendable` closure, so mutable transcripts need a buffered boundary that Terra owns.",
        apiToUse: "Use `Terra.loop(name:id:messages:_:)`, mutate the buffered transcript through `AgentLoopScope`, and use `loop.detached` instead of raw `Task.detached` when parent trace linkage matters.",
        codeExample: """
        var messages = [Terra.ChatMessage(role: "user", content: "Plan the fix.")]
        let result = try await Terra.loop(name: "planner", messages: &messages) { loop in
          loop.checkpoint("planning")
          await loop.appendMessage(.init(role: "assistant", content: "Draft plan"))
          return "ok"
        }
        """,
        commonMistakes: [
          "Capturing `messages` directly inside `Terra.agentic` or `Task.detached`.",
          "Returning before awaited detached transcript mutations finish.",
          "Skipping `Terra.help()` or `Terra.examples()` when choosing the loop shape.",
        ]
      )
    }

    if normalized.contains("agentic workflow") || normalized.contains("agent loop") || normalized.contains("planner") {
      return Guidance(
        why: "Agentic workflows usually include planning, tool calls, and follow-up work that outlive a single model callback. Terra needs one obvious root span owner for the whole turn.",
        apiToUse: "Use `Terra.agentic(name:id:_: )` for multi-step workflows without mutable transcript buffering, or `Terra.loop(name:id:messages:_:)` when the transcript itself must be updated in-place.",
        codeExample: """
        let result = try await Terra.agentic(name: "agent-turn", id: "turn-42") { agent in
          agent.checkpoint("planning")
          let draft = try await agent.infer("local-mlx-model", prompt: "Plan") { "draft" }
          let tool = try await agent.tool("search", callId: "call-42") { "results" }
          return draft + tool
        }
        """,
        commonMistakes: [
          "Using `Terra.stream(...).run` when later tool work needs the same parent span.",
          "Creating a tool span without a stable `callId`.",
          "Using raw `Task.detached` instead of Terra's detached helpers.",
        ]
      )
    }

    if normalized.contains("tool") && normalized.contains("stream") {
      return Guidance(
        why: "Streaming operation closures end before later tool work runs, so the shared parent span must live outside the streaming helper.",
        apiToUse: "Wrap the wider workflow in `Terra.trace(name:id:_:)` or keep a manual parent with `Terra.startSpan(name:id:attributes:)`, then bind the tool with `.under(parent)` when needed.",
        codeExample: """
        let answer = try await Terra.trace(name: "stream-and-tool") { span in
          _ = try await Terra.stream("local-model", prompt: "Explain").run { "draft" }
          return try await Terra.tool("search", callId: "call-1").under(span).run { "docs" }
        }
        """,
        commonMistakes: [
          "Assuming a `.run {}` span remains active after the closure exits.",
          "Ending the parent span before the tool finishes.",
        ]
      )
    }

    if normalized.contains("help") || normalized.contains("discover") || normalized.contains("start here") {
      return Guidance(
        why: "Terra ships a deterministic discovery layer so callers can inspect the intended API map without reading internal source or calling a model.",
        apiToUse: "Print `Terra.help()`, then inspect `Terra.examples()`, `Terra.guides()`, and `Terra.capabilities()` for the exact pattern you need.",
        codeExample: """
        print(Terra.help())
        let capabilities = Terra.capabilities()
        let guides = Terra.guides()
        let examples = Terra.examples()
        """,
        commonMistakes: [
          "Treating `Terra.ask` as an LLM call. It is a deterministic lookup.",
          "Skipping the built-in examples and falling back to source inspection first.",
        ]
      )
    }

    if normalized.contains("quickstart") || normalized.contains("setup") || normalized.contains("diagnose") {
      return Guidance(
        why: "Most onboarding failures are configuration problems, not call-site problems.",
        apiToUse: "Call `Terra.quickStart()` for local development, print `Terra.help()`, and run `Terra.diagnose()` before integrating more tracing code.",
        codeExample: """
        try await Terra.quickStart()
        print(Terra.help())
        let report = Terra.diagnose()
        print(report.suggestions.joined(separator: "\\n"))
        """,
        commonMistakes: [
          "Debugging span propagation before confirming Terra is configured.",
          "Ignoring diagnostic suggestions that point to the right entry point.",
        ]
      )
    }

    if normalized.contains("privacy") || normalized.contains("content") || normalized.contains("redact") {
      return Guidance(
        why: "Terra keeps content capture opt-in so the API remains safe by default.",
        apiToUse: "Keep redacted privacy as the default, then use `.capture(.includeContent)` or the request `includeContent` flag only on the specific operations that require it.",
        codeExample: """
        _ = try await Terra
          .infer("local-model", prompt: "Hello")
          .capture(.includeContent)
          .run { "ok" }
        """,
        commonMistakes: [
          "Assuming `.includeContent` overrides the active privacy policy.",
          "Turning on content capture globally when only one workflow needs it.",
        ]
      )
    }

    if normalized.contains("playground") {
      return Guidance(
        why: "The playground runner is the fastest way to exercise the canonical Terra APIs locally.",
        apiToUse: "Use `Terra.playground()` to list scenarios, then run the scenario that matches your workflow shape.",
        codeExample: """
        let playground = Terra.playground()
        print(playground.scenarios().map(\\.id))
        let result = try await playground.run("trace-basic")
        print(result.summary)
        """,
        commonMistakes: [
          "Expecting the playground to be a general-purpose REPL.",
          "Skipping `Terra.help()` when you need the conceptual map, not just a runnable snippet.",
        ]
      )
    }

    if normalized.contains("trace") || normalized.contains("span") {
      return Guidance(
        why: "Tracing is easiest when one API owns lifecycle and context propagation.",
        apiToUse: "Prefer `Terra.trace(name:id:_:)` for a full async task. Use `Terra.startSpan(name:id:attributes:)` only when lifecycle must stay explicit.",
        codeExample: """
        let value = try await Terra.trace(name: "work") { span in
          span.event("start")
          span.tokens(input: 4, output: 7)
          return "ok"
        }
        """,
        commonMistakes: [
          "Manually starting a span when `Terra.trace` would be simpler.",
          "Expecting `Terra.currentSpan()` to stay non-nil after traced work ends.",
        ]
      )
    }

    return Guidance(
      why: "Terra ships a built-in discovery catalog so callers can inspect capabilities, runnable examples, and diagnostics instead of guessing API shape.",
      apiToUse: "Start with `Terra.help()`, `Terra.examples()`, `Terra.capabilities()`, and `Terra.guides()`, then use `Terra.trace(name:id:_:)` as the default tracing entry point.",
      codeExample: """
      print(Terra.help())
      let report = Terra.diagnose()
      let examples = Terra.examples()
      let capabilities = Terra.capabilities()
      let guides = Terra.guides()
      let result = try await Terra.trace(name: "work") { _ in "ok" }
      """,
      commonMistakes: [
        "Treating `Terra.ask` as an LLM call.",
        "Skipping `Terra.help()` and guessing between overlapping APIs.",
      ]
    )
  }
}

private extension Terra {
  static func _baseExamples() -> [Example] {
    [
      example(
        "Trace Basic Async Work",
        scenario: "I want the default Terra tracing shape for one async task.",
        code: """
        let value = try await Terra.trace(name: "request", id: "req-1") { span in
          span.event("received")
          span.tokens(input: 12, output: 18)
          return "ok"
        }
        """,
        complexity: .beginner
      ),
      example(
        "Trace With Response Model",
        scenario: "I want the root span to capture which model answered.",
        code: """
        let value = try await Terra.trace(name: "answer") { span in
          span.responseModel("local-model")
          return "ok"
        }
        """,
        complexity: .beginner
      ),
      example(
        "Manual Parent Span",
        scenario: "I need a parent span that survives later async work.",
        code: """
        let span = Terra.startSpan(name: "manual-parent", id: "job-1")
        span.event("queued")
        defer { span.end() }
        """,
        complexity: .beginner
      ),
      example(
        "Current Span Inspection",
        scenario: "I want to confirm span propagation inside a traced task.",
        code: """
        let value = try await Terra.trace(name: "debug") { _ in
          print(Terra.currentSpan()?.traceId ?? "missing")
          return "ok"
        }
        """,
        complexity: .beginner
      ),
      example(
        "Diagnose Local Setup",
        scenario: "I want to validate setup before debugging workflow code.",
        code: """
        print(Terra.help())
        let report = Terra.diagnose()
        print(report.suggestions.joined(separator: "\\n"))
        """,
        complexity: .beginner
      ),
      example(
        "Ask For Workflow Guidance",
        scenario: "I want Terra to suggest the right API from plain English intent.",
        code: """
        let guidance = Terra.ask("agent loop with mutable transcript")
        print(guidance.apiToUse)
        """,
        complexity: .beginner
      ),
      example(
        "Read Built-in Capabilities",
        scenario: "I want a machine-readable map of the SDK surface.",
        code: """
        for capability in Terra.capabilities() {
          print("\\(capability.preference.rawValue): \\(capability.entryPoint)")
        }
        """,
        complexity: .beginner
      ),
      example(
        "Read Built-in Guides",
        scenario: "I want copy-paste explanations before integrating a pattern.",
        code: """
        let guides = Terra.guides()
        print(guides.first?.title ?? "missing")
        """,
        complexity: .beginner
      ),
      example(
        "Read Built-in Examples",
        scenario: "I want runnable patterns without leaving the SDK.",
        code: """
        let examples = Terra.examples()
        print(examples.count)
        """,
        complexity: .beginner
      ),
      example(
        "Span Lifecycle Hooks",
        scenario: "I want custom behavior when Terra spans start, end, or fail.",
        code: """
        Terra.onSpanEnd { span, duration in
          print("\\(span.name): \\(duration)")
        }
        _ = try await Terra.trace(name: "hooked") { _ in "ok" }
        Terra.removeHooks()
        """,
        complexity: .intermediate
      ),
      example(
        "Visualize Active Spans",
        scenario: "I want a plain-text hierarchy of active spans while work is running.",
        code: """
        let tree = try await Terra.trace(name: "root") { _ in
          Terra.visualize(Terra.activeSpans())
        }
        print(tree)
        """,
        complexity: .intermediate
      ),
      example(
        "Instrument A Service Wrapper",
        scenario: "I want Terra spans around a stable service interface.",
        code: """
        struct Planner: Terra.TerraInstrumentable {
          let terraServiceName = "planner"
          func terraExecute(_ input: String) async throws -> String { "planned: \\(input)" }
        }
        let service = Planner().instrumented()
        """,
        complexity: .intermediate
      ),
      example(
        "Operation Under Manual Parent",
        scenario: "I want a composable operation to run under an explicit parent span.",
        code: """
        let parent = Terra.startSpan(name: "sync")
        defer { parent.end() }
        _ = try await Terra.tool("search", callId: "call-1").under(parent).run { "ok" }
        """,
        complexity: .intermediate
      ),
      example(
        "Trace Error Remediation",
        scenario: "I want Terra to record an error and show the next action.",
        code: """
        do {
          try await Terra.trace(name: "failing-work") { _ in throw SomeError.failed }
        } catch let error as Terra.TerraError {
          print(error.recoverySuggestion)
        }
        """,
        complexity: .intermediate
      ),
      example(
        "TraceBuilder Compatibility",
        scenario: "I am migrating off the old builder path.",
        code: """
        let builder = Terra.trace(name: "process-request")
        try await builder.span("validation") { }
        builder.end()
        """,
        complexity: .advanced
      ),
    ]
  }

  static func _traceExamples() -> [Example] {
    [
      example(
        "Nested Trace With Child Tool",
        scenario: "I want one root trace and an explicit child tool call.",
        code: """
        let answer = try await Terra.trace(name: "agent-turn") { span in
          span.event("planning")
          return try await Terra.tool("search", callId: "call-1").under(span).run { "docs" }
        }
        """,
        complexity: .intermediate
      ),
      example(
        "Trace And Detached Child Work",
        scenario: "I want detached work to inherit the current Terra span.",
        code: """
        let result = try await Terra.trace(name: "background-sync") { span in
          let task = span.detached { detached in
            detached.event("background.start")
            return "ok"
          }
          return try await task.value
        }
        """,
        complexity: .advanced
      ),
      example(
        "Trace With Custom Attributes",
        scenario: "I want root-level business metadata on a span.",
        code: """
        let value = try await Terra.trace(name: "request") { span in
          span.attribute("app.request.id", "req-7")
          span.attribute("app.retry_count", 2)
          return "ok"
        }
        """,
        complexity: .beginner
      ),
      example(
        "Trace With Privacy-aware Operation Child",
        scenario: "I want the root workflow traced and a child call opted into content capture.",
        code: """
        let value = try await Terra.trace(name: "workflow") { span in
          return try await Terra
            .infer("local-model", prompt: "Hello")
            .under(span)
            .capture(.includeContent)
            .run { "ok" }
        }
        """,
        complexity: .advanced
      ),
      example(
        "Trace With Help Hint",
        scenario: "I want the traced workflow to print Terra's onboarding map.",
        code: """
        let value = try await Terra.trace(name: "start-here") { span in
          span.event("help.printed")
          print(Terra.help())
          return "ok"
        }
        """,
        complexity: .beginner
      ),
    ]
  }

  static func _operationExamples() -> [Example] {
    [
      example(
        "Infer Basic",
        scenario: "I want a traced one-shot inference call.",
        code: """
        _ = try await Terra.infer("local-model", prompt: "Summarize").run { trace in
          trace.tokens(input: 10, output: 14)
          return "ok"
        }
        """,
        complexity: .beginner
      ),
      example(
        "Infer With Messages",
        scenario: "I want an inference call built from chat messages.",
        code: """
        _ = try await Terra.infer(
          "local-model",
          messages: [.init(role: "user", content: "Hello")]
        ).run { "ok" }
        """,
        complexity: .beginner
      ),
      example(
        "Infer With Provider And Runtime",
        scenario: "I want provider/runtime metadata on an inference child span.",
        code: """
        _ = try await Terra.infer(
          "local-model",
          prompt: "Summarize",
          provider: Terra.ProviderID("openai"),
          runtime: Terra.RuntimeID("http_api")
        ).run { "ok" }
        """,
        complexity: .intermediate
      ),
      example(
        "Infer With Custom Tags",
        scenario: "I want operation-scoped custom attributes in an inference helper.",
        code: """
        _ = try await Terra.infer("local-model", prompt: "Summarize").run { trace in
          trace.tag("app.phase", "decode")
          return "ok"
        }
        """,
        complexity: .intermediate
      ),
      example(
        "Infer Under Parent",
        scenario: "I want an inference helper attached under an existing parent span.",
        code: """
        let parent = Terra.startSpan(name: "workflow")
        defer { parent.end() }
        _ = try await Terra.infer("local-model", prompt: "Summarize").under(parent).run { "ok" }
        """,
        complexity: .intermediate
      ),
      example(
        "Stream Basic",
        scenario: "I want to trace a streaming model response.",
        code: """
        _ = try await Terra.stream("local-model", prompt: "Explain").run { trace in
          trace.firstToken()
          trace.chunk(6)
          trace.outputTokens(18)
          return "ok"
        }
        """,
        complexity: .beginner
      ),
      example(
        "Stream With Expected Tokens",
        scenario: "I want progress metadata on a streaming operation.",
        code: """
        _ = try await Terra.stream(
          "local-model",
          prompt: "Explain",
          expectedTokens: 128
        ).run { "ok" }
        """,
        complexity: .intermediate
      ),
      example(
        "Stream Under Parent",
        scenario: "I want a streaming helper under a wider workflow span.",
        code: """
        let value = try await Terra.trace(name: "stream-workflow") { span in
          try await Terra.stream("local-model", prompt: "Explain").under(span).run { "ok" }
        }
        """,
        complexity: .intermediate
      ),
      example(
        "Stream With Provider And Runtime",
        scenario: "I want provider/runtime metadata on a streaming helper.",
        code: """
        _ = try await Terra.stream(
          "local-model",
          prompt: "Explain",
          provider: Terra.ProviderID("openai"),
          runtime: Terra.RuntimeID("http_api")
        ).run { "ok" }
        """,
        complexity: .intermediate
      ),
      example(
        "Stream With Tool Follow-up",
        scenario: "I want a streaming response followed by a tool call under the same root.",
        code: """
        let answer = try await Terra.trace(name: "stream-and-tool") { span in
          _ = try await Terra.stream("local-model", prompt: "Explain").under(span).run { "draft" }
          return try await Terra.tool("search", callId: "call-1").under(span).run { "docs" }
        }
        """,
        complexity: .advanced
      ),
      example(
        "Embed Basic",
        scenario: "I want to trace an embedding request.",
        code: """
        _ = try await Terra.embed("local-embedder", inputCount: 4).run { [0.1, 0.2] }
        """,
        complexity: .beginner
      ),
      example(
        "Embed Under Parent",
        scenario: "I want embeddings under an existing parent span.",
        code: """
        let parent = Terra.startSpan(name: "retrieval")
        defer { parent.end() }
        _ = try await Terra.embed("local-embedder", inputCount: 4).under(parent).run { [0.1, 0.2] }
        """,
        complexity: .intermediate
      ),
      example(
        "Embed With Provider And Runtime",
        scenario: "I want provider/runtime metadata on an embedding call.",
        code: """
        _ = try await Terra.embed(
          "local-embedder",
          inputCount: 4,
          provider: Terra.ProviderID("openai"),
          runtime: Terra.RuntimeID("http_api")
        ).run { [0.1, 0.2] }
        """,
        complexity: .intermediate
      ),
      example(
        "Tool Basic",
        scenario: "I want a traced tool call with a stable call identifier.",
        code: """
        _ = try await Terra.tool("search", callId: "call-1").run { trace in
          trace.event("tool.start")
          return "ok"
        }
        """,
        complexity: .beginner
      ),
      example(
        "Tool Auto-generated Call ID",
        scenario: "I do not already have a tool call identifier.",
        code: """
        _ = try await Terra.tool("search").run { "ok" }
        """,
        complexity: .beginner
      ),
      example(
        "Tool With Type Provider And Runtime",
        scenario: "I want full tool metadata on a child span.",
        code: """
        _ = try await Terra.tool(
          "search",
          callId: "call-1",
          type: "web_search",
          provider: Terra.ProviderID("openai"),
          runtime: Terra.RuntimeID("http_api")
        ).run { "ok" }
        """,
        complexity: .intermediate
      ),
      example(
        "Tool Under Parent",
        scenario: "I want a tool helper attached under an explicit root span.",
        code: """
        let result = try await Terra.trace(name: "tool-workflow") { span in
          try await Terra.tool("search", callId: "call-1").under(span).run { "ok" }
        }
        """,
        complexity: .intermediate
      ),
      example(
        "Safety Basic",
        scenario: "I want to trace a safety evaluation.",
        code: """
        _ = try await Terra.safety("prompt_review", subject: "hello").run { "safe" }
        """,
        complexity: .beginner
      ),
      example(
        "Safety With Provider And Runtime",
        scenario: "I want provider/runtime metadata on a safety evaluation.",
        code: """
        _ = try await Terra.safety(
          "prompt_review",
          subject: "hello",
          provider: Terra.ProviderID("openai"),
          runtime: Terra.RuntimeID("http_api")
        ).run { "safe" }
        """,
        complexity: .intermediate
      ),
      example(
        "Safety Under Parent",
        scenario: "I want a safety evaluation attached under a wider root span.",
        code: """
        let parent = Terra.startSpan(name: "policy-check")
        defer { parent.end() }
        _ = try await Terra.safety("prompt_review", subject: "hello").under(parent).run { "safe" }
        """,
        complexity: .intermediate
      ),
    ]
  }

  static func _loopExamples() -> [Example] {
    [
      example(
        "Loop Basic Transcript Update",
        scenario: "I want the Swift 6-safe pattern for mutating chat history under one root span.",
        code: """
        var messages = [Terra.ChatMessage(role: "user", content: "Plan the fix.")]
        let result = try await Terra.loop(name: "planner", messages: &messages) { loop in
          await loop.appendMessage(.init(role: "assistant", content: "Draft plan"))
          return "ok"
        }
        """,
        complexity: .beginner
      ),
      example(
        "Loop Snapshot Messages",
        scenario: "I want to inspect the buffered transcript mid-loop.",
        code: """
        try await Terra.loop(name: "planner", messages: &messages) { loop in
          let snapshot = await loop.snapshotMessages()
          print(snapshot.count)
          return "ok"
        }
        """,
        complexity: .beginner
      ),
      example(
        "Loop Replace Transcript",
        scenario: "I want to replace the whole transcript after a planning step.",
        code: """
        try await Terra.loop(name: "planner", messages: &messages) { loop in
          await loop.replaceMessages([.init(role: "assistant", content: "Clean slate")])
          return "ok"
        }
        """,
        complexity: .beginner
      ),
      example(
        "Loop Append Multiple Messages",
        scenario: "I want to append several chat messages in one mutation.",
        code: """
        try await Terra.loop(name: "planner", messages: &messages) { loop in
          await loop.appendMessages([
            .init(role: "assistant", content: "Draft"),
            .init(role: "tool", content: "Search results")
          ])
          return "ok"
        }
        """,
        complexity: .beginner
      ),
      example(
        "Loop Checkpoint And Tool Call",
        scenario: "I want transcript mutation plus explicit child operations under one root span.",
        code: """
        try await Terra.loop(name: "planner", messages: &messages) { loop in
          loop.checkpoint("search")
          let docs = try await loop.tool("search", callId: "call-1") { "docs" }
          await loop.appendMessage(.init(role: "tool", content: docs))
          return docs
        }
        """,
        complexity: .advanced
      ),
      example(
        "Loop With Child Inference",
        scenario: "I want the loop to call a model and then persist the answer into the transcript.",
        code: """
        try await Terra.loop(name: "planner", messages: &messages) { loop in
          let draft = try await loop.infer("local-model", prompt: "Plan") { "draft" }
          await loop.appendMessage(.init(role: "assistant", content: draft))
          return draft
        }
        """,
        complexity: .advanced
      ),
      example(
        "Loop Error Still Writes Back",
        scenario: "I want transcript changes to survive even if the loop throws.",
        code: """
        do {
          try await Terra.loop(name: "planner", messages: &messages) { loop in
            await loop.appendMessage(.init(role: "assistant", content: "partial"))
            throw SomeError.failed
          }
        } catch {
          print(messages)
        }
        """,
        complexity: .advanced
      ),
      example(
        "Loop Detached Work",
        scenario: "I want a detached child task that stays attached to the loop span.",
        code: """
        try await Terra.loop(name: "planner", messages: &messages) { loop in
          let task = loop.detached { detached in
            detached.checkpoint("background")
            await detached.appendMessage(.init(role: "assistant", content: "background"))
            return "ok"
          }
          return try await task.value
        }
        """,
        complexity: .advanced
      ),
      example(
        "Loop Clear Transcript",
        scenario: "I want to reset the transcript during a traced loop.",
        code: """
        try await Terra.loop(name: "planner", messages: &messages) { loop in
          await loop.clearMessages()
          return "ok"
        }
        """,
        complexity: .intermediate
      ),
      example(
        "Loop With Existing Transcript",
        scenario: "I want to begin with existing user/system messages and continue the conversation.",
        code: """
        var messages = [
          Terra.ChatMessage(role: "system", content: "You plan fixes."),
          Terra.ChatMessage(role: "user", content: "Investigate the crash.")
        ]
        _ = try await Terra.loop(name: "planner", messages: &messages) { _ in "ok" }
        """,
        complexity: .beginner
      ),
    ]
  }

  static func _debugExamples() -> [Example] {
    [
      example(
        "Help Tree Output",
        scenario: "I want to print Terra's entry-point tree in a debug session.",
        code: """
        print(Terra.help())
        """,
        complexity: .beginner
      ),
      example(
        "Capability Preference Filtering",
        scenario: "I want to separate primary and compatibility entry points.",
        code: """
        let primary = Terra.capabilities().filter { $0.preference == .primary }
        let compatibility = Terra.capabilities().filter { $0.preference == .compatibility }
        """,
        complexity: .beginner
      ),
      example(
        "Guide Lookup By Title",
        scenario: "I want the exact guide for loop transcript mutation.",
        code: """
        let guide = Terra.guides().first { $0.title.contains("Mutable Transcript") }
        print(guide?.solution ?? "missing")
        """,
        complexity: .beginner
      ),
      example(
        "Example Lookup By Title",
        scenario: "I want the exact runnable example for loop error writeback.",
        code: """
        let example = Terra.examples().first { $0.title == "Loop Error Still Writes Back" }
        print(example?.code ?? "missing")
        """,
        complexity: .beginner
      ),
      example(
        "Ask For Setup Guidance",
        scenario: "I want deterministic setup guidance instead of docs spelunking.",
        code: """
        let guidance = Terra.ask("quickstart and diagnose setup")
        print(guidance.apiToUse)
        """,
        complexity: .beginner
      ),
      example(
        "Ask For Privacy Guidance",
        scenario: "I want guidance on redaction and content capture.",
        code: """
        let guidance = Terra.ask("privacy include content")
        print(guidance.codeExample)
        """,
        complexity: .beginner
      ),
      example(
        "Help And Diagnose Together",
        scenario: "I want both the entry-point map and environment validation.",
        code: """
        print(Terra.help())
        let report = Terra.diagnose()
        print(report.suggestions)
        """,
        complexity: .beginner
      ),
      example(
        "TraceHandle Compatibility Access To Span",
        scenario: "I want the operation-scoped compatibility handle to surface the underlying Terra span when available.",
        code: """
        _ = try await Terra.infer("local-model", prompt: "Hello").run { trace in
          print(trace.span?.traceId ?? "missing")
          return "ok"
        }
        """,
        complexity: .intermediate
      ),
      example(
        "Diagnose Inside Active Trace",
        scenario: "I want to validate propagation while a Terra span is active.",
        code: """
        let report = try await Terra.trace(name: "diagnostics") { _ in
          Terra.diagnose()
        }
        print(report.suggestions)
        """,
        complexity: .intermediate
      ),
      example(
        "ASCII And JSON Visualization",
        scenario: "I want both plain-text and JSON active-span views.",
        code: """
        let outputs = try await Terra.trace(name: "root") { _ in
          (Terra.visualize(Terra.activeSpans()), Terra.visualize(Terra.activeSpans(), format: .json))
        }
        print(outputs.0)
        print(outputs.1)
        """,
        complexity: .intermediate
      ),
    ]
  }

  static func _playgroundExamples() -> [Example] {
    [
      example(
        "Playground List Scenarios",
        scenario: "I want to see which local playground scenarios Terra ships.",
        code: """
        let playground = Terra.playground()
        print(playground.scenarios().map(\\.id))
        """,
        complexity: .beginner
      ),
      example(
        "Playground Run Trace Scenario",
        scenario: "I want to run the basic trace playground scenario.",
        code: """
        let result = try await Terra.playground().run("trace-basic")
        print(result.summary)
        """,
        complexity: .beginner
      ),
      example(
        "Playground Run Loop Scenario",
        scenario: "I want to run the mutable transcript loop playground scenario.",
        code: """
        let result = try await Terra.playground().run("loop-messages")
        print(result.recordedEvents)
        """,
        complexity: .beginner
      ),
      example(
        "Playground Run Agentic Scenario",
        scenario: "I want to run the multi-step agentic playground scenario.",
        code: """
        let result = try await Terra.playground().run("agentic-turn")
        print(result.recommendedNextSteps)
        """,
        complexity: .beginner
      ),
      example(
        "Playground Run Diagnostics Scenario",
        scenario: "I want to run the diagnostics playground scenario and inspect the notes.",
        code: """
        let result = try await Terra.playground().run("diagnostics")
        print(result.summary)
        """,
        complexity: .beginner
      ),
      example(
        "Playground Run Streaming Scenario",
        scenario: "I want to run the streaming playground scenario locally.",
        code: """
        let result = try await Terra.playground().run("stream-basic")
        print(result.recordedEvents)
        """,
        complexity: .beginner
      ),
    ]
  }
}
