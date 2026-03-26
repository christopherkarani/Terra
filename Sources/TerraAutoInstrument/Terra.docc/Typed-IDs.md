# Typed IDs

Terra keeps structured wrappers for provider and runtime metadata:

```swift
let provider = Terra.ProviderID("openai")
let runtime = Terra.RuntimeID("http_api")
```

Model names and tool call IDs are plain strings:

```swift
let answer = try await Terra.workflow(name: "request") { workflow in
  let draft = try await workflow.infer("gpt-4o-mini", prompt: "Plan") { "draft" }
  let tool = try await workflow.tool("search", callId: "search-1") { "docs" }
  return draft + tool
}
```
