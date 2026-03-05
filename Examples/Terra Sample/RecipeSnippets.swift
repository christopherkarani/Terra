#if os(macOS)

import Foundation
import Terra

enum TerraRecipeSnippets {
  static let sampleKindKey = Terra.TraceKey<String>("sample.kind")
  static let userTierKey = Terra.TraceKey<String>("app.user_tier")
  static let queryLengthKey = Terra.TraceKey<Int>("tool.query.length")
  static let taskKey = Terra.TraceKey<String>("agent.task")

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
      .metadata {
        Terra.event("infer.request")
        Terra.attr(sampleKindKey, "infer")
      }
      .run { trace in
        trace.attr(userTierKey, "free")
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
      .metadata {
        Terra.event("tool.invoked")
        Terra.attr(sampleKindKey, "tool")
      }
      .attr(queryLengthKey, query.count)
      .run { _ in
        ["result for \(query)"]
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
      .metadata {
        Terra.event("agent.begin")
        Terra.attr(sampleKindKey, "agent")
      }
      .run { trace in
        trace.attr(taskKey, task)
        _ = try await toolRecipe(query: task)
        return try await inferRecipe(prompt: "Plan next steps for: \(task)")
      }
  }
}

#endif
