#if os(macOS)

import Foundation
import Terra

enum TerraRecipeSnippets {

  static func ninetySecondPath(prompt: String = "Give me a short release summary.") async throws -> String {
    try await Terra.start(.init(preset: .quickstart))
    let answer = try await inferRecipe(prompt: prompt)
    await Terra.shutdown()
    return answer
  }

  static func inferRecipe(prompt: String) async throws -> String {
    try await Terra
      .infer(
        Terra.ModelID("gpt-4o-mini"),
        prompt: prompt,
        provider: Terra.ProviderID("openai"),
        runtime: Terra.RuntimeID("http_api")
      )
      .run { trace in
        trace.event("infer.request")
        trace.tag("sample.kind", "infer")
        trace.tag("app.user_tier", "free")
        trace.tokens(input: 42, output: 18)
        return "stubbed-infer-response"
      }
  }

  static func toolRecipe(query: String) async throws -> [String] {
    try await Terra
      .tool(
        "search",
        callID: Terra.ToolCallID("tool-call-1"),
        type: "web_search",
        provider: Terra.ProviderID("openai"),
        runtime: Terra.RuntimeID("http_api")
      )
      .run { trace in
        trace.event("tool.invoked")
        trace.tag("sample.kind", "tool")
        trace.tag("tool.query.length", query.count)
        return ["result for \(query)"]
      }
  }

  static func agentRecipe(task: String) async throws -> String {
    try await Terra
      .agent(
        "planner",
        id: "agent-1",
        provider: Terra.ProviderID("openai"),
        runtime: Terra.RuntimeID("http_api")
      )
      .run { trace in
        trace.event("agent.begin")
        trace.tag("sample.kind", "agent")
        trace.tag("agent.task", task)
        _ = try await toolRecipe(query: task)
        return try await inferRecipe(prompt: "Plan next steps for: \(task)")
      }
  }
}

#endif
