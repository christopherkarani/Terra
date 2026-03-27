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
    await Terra
      .infer(
        "gpt-4o-mini",
        messages: [
          .init(role: "system", content: "You write concise release summaries."),
          .init(role: "user", content: prompt)
        ],
        provider: Terra.ProviderID("openai"),
        runtime: Terra.RuntimeID("http_api")
      )
      .run { span in
        span.event("infer.request")
        span.attribute("sample.kind", "infer")
        span.attribute("app.user_tier", "free")
        span.tokens(input: 42, output: 18)
        return "stubbed-infer-response"
      }
  }

  static func toolRecipe(query: String) async throws -> [String] {
    await Terra
      .tool(
        "search",
        callId: "tool-call-1",
        type: "web_search",
        provider: Terra.ProviderID("openai"),
        runtime: Terra.RuntimeID("http_api")
      )
      .run { span in
        span.event("tool.invoked")
        span.attribute("sample.kind", "tool")
        span.attribute("tool.query.length", query.count)
        return ["result for \(query)"]
      }
  }

  static func workflowRecipe(task: String) async throws -> String {
    try await Terra.workflow(name: "planner", id: "workflow-1") { workflow in
      workflow.event("workflow.start")
      workflow.attribute("sample.kind", "workflow")
      workflow.attribute("workflow.task", task)

      _ = try await workflow.tool(
        "search",
        callId: "workflow-tool-1",
        type: "web_search",
        provider: Terra.ProviderID("openai"),
        runtime: Terra.RuntimeID("http_api")
      ) { span in
        span.event("tool.invoked")
        span.attribute("tool.query.length", task.count)
        return ["result for \(task)"]
      }

      return try await workflow.infer(
        "gpt-4o-mini",
        prompt: "Plan next steps for: \(task)",
        provider: Terra.ProviderID("openai"),
        runtime: Terra.RuntimeID("http_api")
      ) { span in
        span.event("infer.followup")
        span.tokens(input: 24, output: 16)
        return "stubbed-workflow-response"
      }
    }
  }

  static func deferredToolRecipe(task: String) async throws -> String {
    try await Terra.workflow(name: "planner.deferred-tool", id: "workflow-2") { workflow in
      let deferred = try await workflow.stream(
        "gpt-4o-mini",
        prompt: "Decide whether this task needs search: \(task)",
        provider: Terra.ProviderID("openai"),
        runtime: Terra.RuntimeID("http_api")
      ) { span in
        span.firstToken()
        span.chunk(3)
        return try span.handoff().tool(
          "search",
          callId: "workflow-tool-2",
          type: "web_search",
          provider: Terra.ProviderID("openai"),
          runtime: Terra.RuntimeID("http_api")
        )
      }

      return await deferred.run { span in
        span.event("tool.invoked")
        span.attribute("sample.kind", "deferred-tool")
        return "deferred-search-results"
      }
    }
  }
}

#endif
