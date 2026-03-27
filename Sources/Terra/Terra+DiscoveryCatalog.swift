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
        "Print Terra's start-here map before wiring a real workflow.",
        #"print(Terra.help())"#,
        "Terra.help()"
      ),
      capability(
        "workflow_root",
        "Trace one request as a single workflow root with automatic lifecycle.",
        #"let value = try await Terra.workflow(name: "request") { workflow in workflow.event("start"); return "ok" }"#,
        "Terra.workflow(name:id:_:)"
      ),
      capability(
        "workflow_transcript",
        "Trace a workflow that owns buffered transcript mutation and writes back safely.",
        #"let value = try await Terra.workflow(name: "planner", messages: &messages) { workflow, transcript in await transcript.append(.init(role: "assistant", content: "draft")); return "ok" }"#,
        "Terra.workflow(name:id:messages:_:)"
      ),
      capability(
        "manual_span",
        "Create a manual parent when work must outlive a single closure.",
        #"let span = Terra.startSpan(name: "manual"); span.event("queued"); span.end()"#,
        "Terra.startSpan(name:id:attributes:)"
      ),
      capability(
        "tool_handoff",
        "Capture a long-lived parent for tool work that executes after an inference or stream child ends.",
        #"let deferred = try span.handoff().tool("search", callId: "search-1")"#,
        "SpanHandle.handoff(), SpanHandle.withToolParent(_:)",
        preference: .secondary
      ),
      capability(
        "child_operations",
        "Record inference, streaming, tool, embedding, safety, and agent child operations under the current workflow.",
        #"let answer = try await workflow.infer("gpt-4o-mini", prompt: "Summarize") { "ok" }"#,
        "SpanHandle.infer(_:...), SpanHandle.stream(_:...), SpanHandle.tool(_:...), SpanHandle.embed(_:...), SpanHandle.safety(_:...), SpanHandle.agent(_:...)",
        preference: .secondary
      ),
      capability(
        "active_context",
        "Inspect the currently active Terra span in the exact async context you care about.",
        #"if let span = Terra.currentSpan() { print(span.traceId) }"#,
        "Terra.currentSpan()",
        preference: .secondary
      ),
      capability(
        "active_spans",
        "List and visualize active spans to debug parent-child linkage.",
        #"print(Terra.visualize(Terra.activeSpans()))"#,
        "Terra.activeSpans(), Terra.visualize(_:)",
        preference: .secondary
      ),
      capability(
        "diagnose",
        "Check setup issues before debugging the wrong layer.",
        #"let report = Terra.diagnose()"#,
        "Terra.diagnose()"
      ),
      capability(
        "discovery",
        "Ask Terra which pattern to use and inspect runnable examples or guides.",
        #"let guidance = Terra.ask("workflow with tools")"#,
        "Terra.ask(_:), Terra.examples(), Terra.guides()"
      ),
      capability(
        "playground",
        "Run guided local scenarios that exercise the canonical APIs.",
        #"let result = try await Terra.playground().run("workflow-basic")"#,
        "Terra.playground()",
        preference: .secondary
      ),
    ]
  }

  package static var _guideCatalog: [Guide] {
    [
      guide(
        "Start Here",
        problem: "New users need one obvious path into Terra.",
        solution: "Start with `Terra.help()`, then run `Terra.diagnose()` before tracing real model work.",
        codeExample: """
        print(Terra.help())
        let report = Terra.diagnose()
        """
      ),
      guide(
        "Choosing workflow Root",
        problem: "It is unclear how to model one request with multiple child spans.",
        solution: "Use `Terra.workflow(name:id:_:)` for the common case where one request owns the full workflow tree.",
        codeExample: """
        let value = try await Terra.workflow(name: "request", id: "req-1") { workflow in
          workflow.event("request.received")
          return "ok"
        }
        """
      ),
      guide(
        "Mutable Transcript Workflow",
        problem: "`inout [ChatMessage]` cannot be captured safely inside sendable async closures.",
        solution: "Use `Terra.workflow(name:id:messages:_:)` and mutate the `WorkflowTranscript` helper instead of the caller array directly.",
        codeExample: """
        var messages = [Terra.ChatMessage(role: "user", content: "Plan the fix.")]
        let value = try await Terra.workflow(name: "planner", messages: &messages) { workflow, transcript in
          workflow.checkpoint("planning")
          await transcript.append(.init(role: "assistant", content: "Draft plan"))
          return "ok"
        }
        """
      ),
      guide(
        "Transcript Writeback",
        problem: "Users need to know when buffered transcript mutations are persisted.",
        solution: "`Terra.workflow(messages:)` writes the final transcript back on both success and failure. Await detached work before returning if those mutations must persist.",
        codeExample: """
        try await Terra.workflow(name: "planner", messages: &messages) { workflow, transcript in
          let task = workflow.detached { _ in
            await transcript.append(.init(role: "assistant", content: "late"))
            return ()
          }
          try await task.value
          return "done"
        }
        """
      ),
      guide(
        "Manual Lifecycle",
        problem: "Some workflows need a parent span that survives beyond a closure boundary.",
        solution: "Use `Terra.startSpan(name:id:attributes:)` only when `Terra.workflow` cannot own the lifecycle cleanly.",
        codeExample: """
        let span = Terra.startSpan(name: "manual")
        span.event("queued")
        defer { span.end() }
        """
      ),
      guide(
        "Inference Child Span",
        problem: "Inference should be obvious and safely parented under the workflow root.",
        solution: "Use `workflow.infer(...)` inside the root body so the child span is attached automatically.",
        codeExample: """
        let answer = try await Terra.workflow(name: "chat") { workflow in
          try await workflow.infer("gpt-4o-mini", prompt: "Summarize") { span in
            span.tokens(input: 12, output: 18)
            return "summary"
          }
        }
        """
      ),
      guide(
        "Streaming Child Span",
        problem: "Streaming token telemetry is easy to get wrong in async code.",
        solution: "Keep a workflow root outside the stream and record `firstToken`, `chunk`, and `outputTokens` on the streaming child span.",
        codeExample: """
        try await Terra.workflow(name: "chat") { workflow in
          try await workflow.stream("gpt-4o-mini", prompt: "Explain") { span in
            span.firstToken()
            span.chunk(4)
            span.outputTokens(12)
            return "done"
          }
        }
        """
      ),
      guide(
        "Tool Child Span",
        problem: "Tool calls should stay attached to the root with a stable call identifier.",
        solution: "Use `workflow.tool(..., callId:)` for each tool invocation inside the root workflow.",
        codeExample: """
        try await Terra.workflow(name: "planner") { workflow in
          try await workflow.tool("search", callId: "search-1", type: "web_search") { span in
            span.event("tool.invoked")
            return "docs"
          }
        }
        """
      ),
      guide(
        "Embedding Child Span",
        problem: "Embedding telemetry should look like a first-class child operation, not a special case.",
        solution: "Use `workflow.embed(...)` under the same workflow root so model usage stays visible in one tree.",
        codeExample: """
        try await Terra.workflow(name: "semantic-search") { workflow in
          try await workflow.embed("text-embedding-3-small", inputCount: 2) { _ in
            [[0.1, 0.2], [0.3, 0.4]]
          }
        }
        """
      ),
      guide(
        "Safety Child Span",
        problem: "Safety checks are part of the workflow and should be visible beside model and tool work.",
        solution: "Use `workflow.safety(...)` as a child span instead of leaving the check untraced.",
        codeExample: """
        try await Terra.workflow(name: "guarded-chat") { workflow in
          try await workflow.safety("prompt-review", subject: "hello") { "safe" }
        }
        """
      ),
      guide(
        "Nested Agent Span",
        problem: "Some workflows contain a nested planning or routing phase that should still be explicit.",
        solution: "Use `workflow.agent(...)` when the workflow contains a nested agentic phase but the root still belongs to one request.",
        codeExample: """
        try await Terra.workflow(name: "request") { workflow in
          try await workflow.agent("planner", id: "planner-1") { span in
            span.checkpoint("plan")
            return "ok"
          }
        }
        """
      ),
      guide(
        "Detached Work",
        problem: "Raw `Task.detached` drops Terra context.",
        solution: "Use `SpanHandle.detached(...)` from the active workflow root when background work must stay linked.",
        codeExample: """
        try await Terra.workflow(name: "request") { workflow in
          let task = workflow.detached { detached in
            detached.event("background.work")
            return "ok"
          }
          return try await task.value
        }
        """
      ),
      guide(
        "Current Span Inspection",
        problem: "Propagation issues are hard to debug without checking the exact async context.",
        solution: "Call `Terra.currentSpan()` or `Terra.isTracing()` inside the async context you want to verify.",
        codeExample: """
        try await Terra.workflow(name: "debug") { _ in
          print(Terra.isTracing())
          print(Terra.currentSpan()?.traceId ?? "none")
          return "ok"
        }
        """
      ),
      guide(
        "Visualize Active Spans",
        problem: "Terminal debugging benefits from a plain text tree view.",
        solution: "Use `Terra.activeSpans()` and `Terra.visualize(...)` to inspect the current hierarchy.",
        codeExample: """
        let tree = try await Terra.workflow(name: "root") { _ in
          Terra.visualize(Terra.activeSpans())
        }
        print(tree)
        """
      ),
      guide(
        "Response Model And Tokens",
        problem: "Model usage metadata should be recorded through one consistent surface.",
        solution: "Use `SpanHandle.tokens(...)` and `SpanHandle.responseModel(...)` in both root and child closures.",
        codeExample: """
        try await Terra.workflow(name: "chat") { workflow in
          workflow.tokens(input: 4, output: 7)
          workflow.responseModel("gpt-4o-mini")
          return "ok"
        }
        """
      ),
      guide(
        "Deferred Tool Handoff",
        problem: "A tool call may be discovered inside an inference or stream child span, but executed only after that child span ends.",
        solution: "Capture `span.handoff()` while the wider workflow or manual parent is still alive, then build the later tool call from that handoff instead of reusing the child span itself.",
        codeExample: """
        let docs = try await Terra.workflow(name: "stream-and-tool") { workflow in
          let deferred = try await workflow.stream("gpt-4o-mini", prompt: "Explain") { span in
            span.firstToken()
            return try span.handoff().tool("search", callId: "search-1")
          }
          return try await deferred.run { "docs" }
        }
        """
      ),
      guide(
        "Manual Parent For Later Work",
        problem: "A tool call may need an explicit parent chosen outside its closure.",
        solution: "Use `Terra.startSpan(...)` only when the parent lifecycle truly must outlive the wider workflow body, then keep that parent alive until the later tool call is created.",
        codeExample: """
        let parent = Terra.startSpan(name: "manual-parent")
        defer { parent.end() }
        _ = try await Terra.tool("search", callId: "search-1").under(parent).run { "ok" }
        """
      ),
      guide(
        "Privacy Opt-In",
        problem: "Content capture is opt-in per operation and easy to miss.",
        solution: "Keep Terra redacted by default and use `.capture(.includeContent)` only where content telemetry is justified.",
        codeExample: """
        _ = try await Terra
          .infer("gpt-4o-mini", prompt: "Hello")
          .capture(.includeContent)
          .run { "ok" }
        """
      ),
      guide(
        "Diagnostics First",
        problem: "Missing providers or endpoints often look like tracing bugs.",
        solution: "Run `Terra.diagnose()` before debugging workflow code so you fix setup first.",
        codeExample: """
        let report = Terra.diagnose()
        print(report.suggestions.joined(separator: "\\n"))
        """
      ),
      guide(
        "Using help And ask",
        problem: "New users often know the workflow shape but not Terra's vocabulary.",
        solution: "Use `Terra.help()` for the map, then `Terra.ask(...)` for the closest copy-paste pattern.",
        codeExample: """
        print(Terra.help())
        let guidance = Terra.ask("workflow with tools")
        print(guidance.apiToUse)
        """
      ),
      guide(
        "Service Instrumentation",
        problem: "A service API should stay stable when Terra tracing is added.",
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
        "Choosing workflow Messages",
        problem: "Users need a crisp boundary between root-only workflows and transcript workflows.",
        solution: "Use `Terra.workflow(name:id:_:)` when the root owns child spans only. Use `Terra.workflow(name:id:messages:_:)` when the transcript itself must be mutated safely.",
        codeExample: """
        let rootOnly = try await Terra.workflow(name: "request") { _ in "ok" }
        let transcript = try await Terra.workflow(name: "planner", messages: &messages) { _, transcript in
          await transcript.append(.init(role: "assistant", content: "draft"))
          return "ok"
        }
        """
      ),
    ]
  }

  package static var _exampleCatalog: [Example] {
    var examples: [Example] = [
      example(
        "Workflow Root",
        scenario: "Trace one request with a root workflow span.",
        code: """
        let value = try await Terra.workflow(name: "request", id: "req-1") { workflow in
          workflow.event("request.start")
          return "ok"
        }
        """,
        complexity: .beginner
      ),
      example(
        "Workflow Messages",
        scenario: "Trace a workflow that mutates buffered transcript state.",
        code: """
        var messages = [Terra.ChatMessage(role: "user", content: "Plan the fix.")]
        let result = try await Terra.workflow(name: "planner", messages: &messages) { workflow, transcript in
          workflow.checkpoint("planning")
          await transcript.append(.init(role: "assistant", content: "Draft plan"))
          return "ok"
        }
        """,
        complexity: .beginner
      ),
      example(
        "Help And Diagnose",
        scenario: "Inspect the start-here map and local setup fixes.",
        code: """
        print(Terra.help())
        let report = Terra.diagnose()
        print(report.suggestions)
        """,
        complexity: .beginner
      ),
      example(
        "Playground",
        scenario: "Run a guided local scenario.",
        code: """
        let playground = Terra.playground()
        let result = try await playground.run("workflow-basic")
        print(result.summary)
        """,
        complexity: .beginner
      ),
      example(
        "Instrumented Service",
        scenario: "Wrap a service without changing its public method shape.",
        code: """
        struct Planner: Terra.TerraInstrumentable {
          let terraServiceName = "planner"
          func terraExecute(_ input: String) async throws -> String { input }
        }

        let service = Planner().instrumented()
        let value = try await service.terraExecute("triage")
        """,
        complexity: .intermediate
      ),
    ]

    let models = ["gpt-4o-mini", "gpt-4.1-mini", "local-model", "mlx-model", "safety-model"]
    for model in models {
      examples.append(
        example(
          "Infer \(model)",
          scenario: "Run a traced inference child span.",
          code: """
          let value = try await Terra.workflow(name: "chat.\(model)") { workflow in
            try await workflow.infer("\(model)", prompt: "Summarize") { span in
              span.tokens(input: 12, output: 18)
              return "ok"
            }
          }
          """,
          complexity: .beginner
        )
      )
      examples.append(
        example(
          "Stream \(model)",
          scenario: "Run a traced streaming child span.",
          code: """
          let value = try await Terra.workflow(name: "stream.\(model)") { workflow in
            try await workflow.stream("\(model)", prompt: "Explain") { span in
              span.firstToken()
              span.chunk(4)
              span.outputTokens(12)
              return "ok"
            }
          }
          """,
          complexity: .intermediate
        )
      )
    }

    let tools = ["search", "calculator", "filesystem", "browser", "retrieval"]
    for (index, tool) in tools.enumerated() {
      examples.append(
        example(
          "Tool \(tool)",
          scenario: "Trace a child tool call under a workflow root.",
          code: """
          let value = try await Terra.workflow(name: "tool.\(tool)") { workflow in
            try await workflow.tool("\(tool)", callId: "call-\(index + 1)") { span in
              span.event("tool.invoked")
              return "ok"
            }
          }
          """,
          complexity: .beginner
        )
      )
      examples.append(
        example(
          "Workflow With \(tool)",
          scenario: "Run inference followed by a tool inside the same workflow.",
          code: """
          let value = try await Terra.workflow(name: "workflow.\(tool)") { workflow in
            let draft = try await workflow.infer("gpt-4o-mini", prompt: "Need \(tool)") { "draft" }
            let toolResult = try await workflow.tool("\(tool)", callId: "call-\(index + 10)") { "tool" }
            return draft + toolResult
          }
          """,
          complexity: .intermediate
        )
      )
    }

    let transcriptPrompts = ["plan", "summarize", "triage", "research", "answer"]
    for prompt in transcriptPrompts {
      examples.append(
        example(
          "Transcript \(prompt)",
          scenario: "Mutate buffered workflow transcript safely.",
          code: """
          var messages = [Terra.ChatMessage(role: "user", content: "\(prompt)")]
          let value = try await Terra.workflow(name: "messages.\(prompt)", messages: &messages) { workflow, transcript in
            workflow.event("workflow.start")
            await transcript.append(.init(role: "assistant", content: "draft"))
            return "ok"
          }
          """,
          complexity: .intermediate
        )
      )
    }

    let diagnostics = ["help", "ask", "diagnose", "visualize", "current-span"]
    for topic in diagnostics {
      let code: String
      switch topic {
      case "help":
        code = #"print(Terra.help())"#
      case "ask":
        code = #"let guidance = Terra.ask("workflow with tools")"#
      case "diagnose":
        code = "let report = Terra.diagnose()"
      case "visualize":
        code = """
        let tree = try await Terra.workflow(name: "debug") { _ in
          Terra.visualize(Terra.activeSpans())
        }
        """
      default:
        code = """
        let value = try await Terra.workflow(name: "debug") { _ in
          Terra.currentSpan()?.traceId ?? "none"
        }
        """
      }

      examples.append(
        example(
          "Discovery \(topic)",
          scenario: "Use Terra's built-in discovery tools.",
          code: code,
          complexity: .beginner
        )
      )
    }

    let manuals = ["manual-parent", "manual-tool", "manual-stream", "manual-detached", "manual-safety"]
    for item in manuals {
      examples.append(
        example(
          "Manual \(item)",
          scenario: "Use an explicit parent span when lifecycle must be manual.",
          code: """
          let parent = Terra.startSpan(name: "\(item)")
          defer { parent.end() }
          _ = try await Terra.tool("search", callId: "\(item)-call").under(parent).run { "ok" }
          """,
          complexity: .advanced
        )
      )
    }

    let embedExamples = ["documents", "chunks", "queries", "memory", "rerank"]
    for item in embedExamples {
      examples.append(
        example(
          "Embed \(item)",
          scenario: "Record an embedding child span under a workflow root.",
          code: """
          let vectors = try await Terra.workflow(name: "embed.\(item)") { workflow in
            try await workflow.embed("text-embedding-3-small", inputCount: 3) { _ in
              [[0.1, 0.2, 0.3]]
            }
          }
          """,
          complexity: .intermediate
        )
      )
    }

    let safetyExamples = ["prompt", "output", "tool", "upload", "policy"]
    for item in safetyExamples {
      examples.append(
        example(
          "Safety \(item)",
          scenario: "Record a safety child span under a workflow root.",
          code: """
          let decision = try await Terra.workflow(name: "safety.\(item)") { workflow in
            try await workflow.safety("\(item)-review", subject: "\(item)") { "safe" }
          }
          """,
          complexity: .intermediate
        )
      )
    }

    let detachedExamples = ["tool", "stream", "embed", "audit", "writeback"]
    for item in detachedExamples {
      examples.append(
        example(
          "Detached \(item)",
          scenario: "Carry workflow context into detached work.",
          code: """
          let value = try await Terra.workflow(name: "detached.\(item)") { workflow in
            let task = workflow.detached { detached in
              detached.event("background.\(item)")
              return "ok"
            }
            return try await task.value
          }
          """,
          complexity: .advanced
        )
      )
    }

    return examples
  }

  package static func _helpTree() -> String {
    let primary = _capabilityCatalog.filter { $0.preference == .primary }
    let secondary = _capabilityCatalog.filter { $0.preference == .secondary }

    func lines(for capabilities: [Capability]) -> String {
      capabilities
        .map { "- \($0.entryPoint): \($0.description)" }
        .joined(separator: "\n")
    }

    return """
    Terra Help

    Start Here
    - print(Terra.help())
    - let report = Terra.diagnose()
    - let guidance = Terra.ask("workflow with tools")

    Primary APIs
    \(lines(for: primary))

    Secondary APIs
    \(lines(for: secondary))

    Discovery Shortcuts
    - Terra.examples(): \(examples().count) runnable snippets
    - Terra.guides(): \(guides().count) copy-paste guides
    - Terra.playground(): guided local scenario runner
    """
  }

  package static func _guidance(for question: String) -> Guidance {
    let normalized = question.lowercased()

    if normalized.contains("tool") && normalized.contains("stream") {
      return Guidance(
        why: "A streaming child span ends when its closure returns. Tool work emitted mid-stream must be rebound to a wider workflow or manual parent before that child span closes.",
        apiToUse: "Use `Terra.workflow(name:id:_:)` for the full request, then capture `span.handoff()` or use `span.withToolParent(...)` inside the stream closure. Use `Terra.startSpan(name:id:attributes:)` only when the parent lifecycle must be manual beyond the workflow body.",
        codeExample: """
        let docs = try await Terra.workflow(name: "stream-and-tool") { workflow in
          let deferred = try await workflow.stream("gpt-4o-mini", prompt: "Explain") { span in
            span.firstToken()
            return try span.handoff().tool("search", callId: "search-1")
          }
          return try await deferred.run { "docs" }
        }
        """,
        commonMistakes: [
          "Assuming a child operation closure stays open for later work after it returns.",
          "Holding onto the streaming child span instead of handing later tool work off to the wider parent.",
          "Ending the workflow/manual parent before the deferred tool span is created.",
          "Launching detached work from the stream closure without preserving the parent context.",
        ]
      )
    }

    if normalized.contains("message")
      || normalized.contains("transcript")
      || normalized.contains("chat history")
      || normalized.contains("inout")
    {
      return Guidance(
        why: "`inout [ChatMessage]` is not a safe async boundary. Terra needs to own the buffered transcript inside the workflow body.",
        apiToUse: "Use `Terra.workflow(name:id:messages:_:)` and mutate the `WorkflowTranscript` helper from inside the closure.",
        codeExample: """
        var messages = [Terra.ChatMessage(role: "user", content: "Plan the fix.")]
        let result = try await Terra.workflow(name: "planner", messages: &messages) { workflow, transcript in
          workflow.checkpoint("planning")
          await transcript.append(.init(role: "assistant", content: "Draft plan"))
          return try await workflow.tool("search", callId: "search-1") { "ok" }
        }
        """,
        commonMistakes: [
          "Capturing the caller's `messages` array directly inside detached work.",
          "Returning before awaited transcript mutations finish.",
          "Using manual spans when a workflow transcript would be clearer.",
        ]
      )
    }

    if normalized.contains("tool") || normalized.contains("workflow") || normalized.contains("planner") {
      return Guidance(
        why: "Multi-step requests should read as one root workflow with obvious children.",
        apiToUse: "Use `Terra.workflow(name:id:_:)` as the root, then call `workflow.tool(...)`, `workflow.infer(...)`, or `workflow.stream(...)` for children.",
        codeExample: """
        let result = try await Terra.workflow(name: "planner", id: "turn-42") { workflow in
          workflow.checkpoint("planning")
          let draft = try await workflow.infer("gpt-4o-mini", prompt: "Plan") { "draft" }
          let tool = try await workflow.tool("search", callId: "search-1") { "results" }
          return draft + tool
        }
        """,
        commonMistakes: [
          "Starting with a child operation when the request actually has multiple steps.",
          "Ending a manual span too early.",
          "Using raw `Task.detached` instead of `workflow.detached`.",
        ]
      )
    }

    if normalized.contains("stream") {
      return Guidance(
        why: "Streaming needs a stable root outside the stream body so later child work and token telemetry stay attached.",
        apiToUse: "Use `Terra.workflow(name:id:_:)` for the root and `workflow.stream(...)` for the streaming child span.",
        codeExample: """
        let result = try await Terra.workflow(name: "streaming-chat") { workflow in
          try await workflow.stream("gpt-4o-mini", prompt: "Explain") { span in
            span.firstToken()
            span.chunk(4)
            span.outputTokens(12)
            return "ok"
          }
        }
        """,
        commonMistakes: [
          "Using `firstToken`, `chunk`, or `outputTokens` on a non-streaming span.",
          "Treating a streaming child span as the workflow root.",
        ]
      )
    }

    if normalized.contains("help") || normalized.contains("discover") || normalized.contains("start here") {
      return Guidance(
        why: "Terra ships a deterministic discovery layer so you can find the right pattern without reading internal source.",
        apiToUse: "Start with `Terra.help()`, then inspect `Terra.guides()`, `Terra.examples()`, and `Terra.capabilities()`.",
        codeExample: """
        print(Terra.help())
        let guides = Terra.guides()
        let examples = Terra.examples()
        """,
        commonMistakes: [
          "Treating `Terra.ask` as a model call. It is deterministic and offline.",
          "Skipping `Terra.diagnose()` when setup might be the real problem.",
        ]
      )
    }

    return Guidance(
      why: "The default Terra path is workflow-first. Start from the root request shape and add child operations under it.",
      apiToUse: "Use `Terra.workflow(name:id:_:)` for the root, or `Terra.startSpan(name:id:attributes:)` only when lifecycle must remain explicit.",
      codeExample: """
      let value = try await Terra.workflow(name: "request") { workflow in
        workflow.event("request.start")
        return "ok"
      }
      """,
      commonMistakes: [
        "Starting with manual span lifecycle when a workflow root would be simpler.",
        "Assuming child operations can replace the root workflow boundary.",
      ]
    )
  }
}
