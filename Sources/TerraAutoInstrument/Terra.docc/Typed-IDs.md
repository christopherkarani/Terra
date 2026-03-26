# Typed IDs

Use Terra's typed identifiers instead of raw strings when building calls.

> **Note:** `ModelID` and `ToolCallID` are compatibility wrappers retained for older call sites.
> New code should pass model names and tool call IDs as `String` values directly, while
> `ProviderID` and `RuntimeID` remain the structured wrappers for provider/runtime attribution.

## Types

- ``Terra/ModelID``
- ``Terra/ProviderID``
- ``Terra/RuntimeID``
- ``Terra/ToolCallID``

## Why This Matters

- Better call-site clarity.
- Fewer argument mix-ups across provider/runtime/model fields.
- Reusable constants for app-wide consistency.

## Example

```swift
import Terra

let model = "gpt-4o-mini"
let provider = Terra.ProviderID("openai")
let runtime = Terra.RuntimeID("http_api")
let toolCallID = "call-42"

_ = try await Terra
  .infer(model, prompt: "Hello", provider: provider, runtime: runtime)
  .run { "ok" }

_ = try await Terra
  .tool("search", callId: toolCallID, provider: provider, runtime: runtime)
  .run { ["result"] }
```

## Protocol Conformance

All typed IDs conform to ``Codable``, ``Hashable``, and ``Sendable``:

```swift
public struct ModelID: Codable, Hashable, Sendable
public struct ProviderID: Codable, Hashable, Sendable
public struct RuntimeID: Codable, Hashable, Sendable
public struct ToolCallID: Codable, Hashable, Sendable
```

This enables:
- **Codable**: JSON encoding/decoding for network transmission
- **Hashable**: Usage as dictionary keys and in `Set` collections
- **Sendable**: Safe usage across concurrency contexts

Continue with <doc:Metadata-Builder> to add structured metadata.
