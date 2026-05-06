import Foundation
import TerraCore
import Testing

// MARK: - P1-15 Cookbook snippet compilation harness
//
// `Scripts/validate-doc-snippets.py` is a string-matcher; it does not type-check
// fenced ```swift``` blocks in markdown. Stale snippets in
// `README.md`, `Docs/cookbook.md`, `Docs/integrations.md`, and the DocC
// catalog can therefore reference removed types, wrong parameter labels, or
// changed return types and pass validation silently.
//
// This file is a *manual mirror* of every canonical recipe published in the
// cookbook surfaces. Each recipe is copied verbatim into a real Swift function
// in this test target; if the cookbook code stops compiling, the build breaks
// here and CI catches it before docs ship.
//
// Limitation: this is a manual mirror. A future improvement would auto-extract
// fenced code blocks at build time (see P1-15). The annotation comments
// (`// SNIPPET: <doc>#<section>`) make it easy for a CI script to verify
// every fenced ```swift``` block has a corresponding mirror function.
//
// The functions below are `private` and never invoked at runtime — their
// purpose is solely to confirm compilation against the live public API.
// Returning a constant value satisfies any non-Void return type so the bodies
// stay close to the published prose.

@Suite("Cookbook snippet compilation", .serialized)
struct CookbookSnippetsCompileTests {
  @Test("Cookbook snippet mirrors compile against current public API")
  func cookbookSnippetMirrorsCompileAgainstCurrentPublicAPI() {
    // The genuine assertion is "this file compiles". If we got this far, the
    // mirror functions in this file built successfully and the cookbook
    // recipes match the live API surface.
    #expect(Bool(true))
  }
}

// MARK: - README.md mirrors

// SNIPPET: README.md#start-here
//
// The README's "Start Here" recipe shows `print(Terra.help())` for human
// inspection. The mirror exercises the same return signature without writing
// to stdout — type-checking is what we want from this harness, not runtime
// I/O. The `_ =` discards keep the call sites identical to the published API.
private func snippet_readme_startHere() {
  _ = Terra.help()
  let report = Terra.diagnose()
  _ = report
}

// SNIPPET: README.md#canonical-root
private func snippet_readme_canonicalRoot() async throws -> String {
  let answer = try await Terra.workflow(name: "chat.request", id: "req-1") { workflow in
    workflow.event("request.received")

    let draft = try await workflow.infer(
      "gpt-4o-mini",
      prompt: "Summarize the latest issue"
    ) { span in
      span.tokens(input: 24, output: 14)
      return "draft"
    }

    let toolResult = try await workflow.tool(
      "search",
      callId: "search-1",
      type: "web_search"
    ) { span in
      span.event("tool.invoked")
      return "docs"
    }

    return draft + toolResult
  }
  return answer
}

// SNIPPET: README.md#mutable-transcript
private func snippet_readme_mutableTranscript() async throws -> String {
  var messages = [Terra.ChatMessage(role: "user", content: "Plan the fix.")]

  let result = try await Terra.workflow(name: "planner", messages: &messages) { workflow, transcript in
    workflow.checkpoint("planning")
    await transcript.append(.init(role: "assistant", content: "Draft plan"))
    return "ok"
  }
  return result
}

// SNIPPET: README.md#streaming
private func snippet_readme_streaming() async throws -> String {
  let streamed = try await Terra.workflow(name: "stream.request") { workflow in
    try await workflow.stream("gpt-4o-mini", prompt: "Explain") { span in
      span.firstToken()
      span.chunk(4)
      span.outputTokens(12)
      return "done"
    }
  }
  return streamed
}

// SNIPPET: README.md#deferred-tool-after-stream
private func snippet_readme_deferredToolAfterStream() async throws -> String {
  let answer = try await Terra.workflow(name: "stream.and.tool") { workflow in
    let deferred = try await workflow.stream("gpt-4o-mini", prompt: "Explain") { span in
      span.firstToken()
      span.chunk(4)
      return try span.handoff().tool("search", callId: "search-1", type: "web_search")
    }

    let toolResult = try await deferred.run { "docs" }
    return toolResult
  }
  return answer
}

// SNIPPET: README.md#manual-parent
private func snippet_readme_manualParent() async throws {
  let parent = Terra.startSpan(name: "manual.request")
  defer { parent.end() }

  _ = try await Terra.tool("search", callId: "manual-1").under(parent).run { "ok" }
}

// MARK: - Docs/cookbook.md mirrors

// SNIPPET: cookbook.md#chat-request
private func snippet_cookbook_chatRequest() async throws -> String {
  let answer = try await Terra.workflow(name: "chat.request", id: "req-1") { workflow in
    try await workflow.infer("gpt-4o-mini", prompt: "Summarize this thread") { span in
      span.tokens(input: 20, output: 12)
      return "summary"
    }
  }
  return answer
}

// SNIPPET: cookbook.md#streaming-generation
private func snippet_cookbook_streamingGeneration() async throws -> String {
  let answer = try await Terra.workflow(name: "chat.stream", id: "req-2") { workflow in
    try await workflow.stream("gpt-4o-mini", prompt: "Explain the fix") { span in
      span.firstToken()
      span.chunk(5)
      span.outputTokens(18)
      return "streamed"
    }
  }
  return answer
}

// SNIPPET: cookbook.md#deferred-tool-handoff
private func snippet_cookbook_deferredToolHandoff() async throws -> String {
  let result = try await Terra.workflow(name: "tool.after.stream", id: "req-2b") { workflow in
    let deferred = try await workflow.stream("gpt-4o-mini", prompt: "Explain the fix") { span in
      span.firstToken()
      span.chunk(5)
      return try span.handoff().tool("search", callId: "search-2", type: "web_search")
    }

    return try await deferred.run { "docs" }
  }
  return result
}

// SNIPPET: cookbook.md#tool-execution
private func snippet_cookbook_toolExecution() async throws -> String {
  let result = try await Terra.workflow(name: "tool.request", id: "req-3") { workflow in
    try await workflow.tool("search", callId: "search-1", type: "web_search") { span in
      span.event("tool.invoked")
      return "docs"
    }
  }
  return result
}

// SNIPPET: cookbook.md#agent-loop
private func snippet_cookbook_agentLoop() async throws -> String {
  let result = try await Terra.workflow(name: "agent.request", id: "req-4") { workflow in
    workflow.checkpoint("planning")
    let draft = try await workflow.infer("gpt-4o-mini", prompt: "Plan") { "draft" }
    let lookup = try await workflow.tool("search", callId: "search-2") { "lookup" }
    return draft + lookup
  }
  return result
}

// SNIPPET: cookbook.md#mutable-transcript
private func snippet_cookbook_mutableTranscript() async throws -> String {
  var messages = [Terra.ChatMessage(role: "user", content: "Plan the fix.")]

  let result = try await Terra.workflow(name: "planner", messages: &messages) { workflow, transcript in
    workflow.checkpoint("planning")
    await transcript.append(.init(role: "assistant", content: "Draft plan"))
    return "ok"
  }
  return result
}

// SNIPPET: cookbook.md#detached-work
private func snippet_cookbook_detachedWork() async throws -> String {
  let value = try await Terra.workflow(name: "background.sync") { workflow in
    let task = workflow.detached { detached in
      detached.event("background.started")
      return "ok"
    }
    return try await task.value
  }
  return value
}

// SNIPPET: cookbook.md#manual-parent
private func snippet_cookbook_manualParent() async throws {
  let parent = Terra.startSpan(name: "manual.parent")
  defer { parent.end() }

  _ = try await Terra.tool("search", callId: "manual-1").under(parent).run { "ok" }
}
