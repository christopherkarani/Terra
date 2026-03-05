# Typed IDs

Use Terra's typed identifiers instead of raw strings when building calls.

## Types

- ``TerraCore/Terra/ModelID``
- ``TerraCore/Terra/ProviderID``
- ``TerraCore/Terra/RuntimeID``
- ``TerraCore/Terra/ToolCallID``

## Why This Matters

- Better call-site clarity.
- Fewer argument mix-ups across provider/runtime/model fields.
- Reusable constants for app-wide consistency.

## Example

```swift
import Terra

let model = Terra.ModelID("gpt-4o-mini")
let provider = Terra.ProviderID("openai")
let runtime = Terra.RuntimeID("http_api")
let toolCallID = Terra.ToolCallID("call-42")

_ = try await Terra
  .infer(model, prompt: "Hello", provider: provider, runtime: runtime)
  .run { "ok" }

_ = try await Terra
  .tool("search", callID: toolCallID, provider: provider, runtime: runtime)
  .run { ["result"] }
```

Continue with <doc:Metadata-Builder> to add structured metadata.
