# Foundation Models

`TerraTracedSession` uses string model identifiers and records inference spans through Terra.

```swift
let session = TerraTracedSession(modelIdentifier: "apple/foundation-model")
let answer = try await session.respond(to: "Summarize this note")
```

Use a workflow root when the session call is one step inside a wider request:

```swift
let answer = try await Terra.workflow(name: "assistant.request") { workflow in
  workflow.event("foundation-models.begin")
  let session = TerraTracedSession(modelIdentifier: "apple/foundation-model")
  return try await session.respond(to: "Draft a reply")
}
```
