# cookbook.md Audit

Audited against:
- `Sources/Terra/Terra+ComposableAPI.swift`
- `Sources/Terra/Terra+FluentAPI.swift`
- `Sources/Terra/Terra+Requests.swift`
- `Sources/TerraFoundationModels/TerraTracedSession.swift`
- `Sources/TerraMLX/TerraMLX.swift`

---

## CRITICAL: `.provider()` does not exist on `Operation`

**Location:** cookbook.md, multiple locations (Inference with metadata, Safety Pipeline, Custom Attributes, Multi-Tenant Privacy, Agent Workflow)

**DOCUMENTED AS:**
```swift
Terra.infer(
    Terra.ModelID("gpt-4o-mini"),
    prompt: prompt,
    provider: Terra.ProviderID("openai"),  // <-- on Operation
    runtime: Terra.RuntimeID("http_api")
)
```

**ACTUAL API:**
- `Terra.infer(_ model: ModelID, prompt: String?, provider: ProviderID?, runtime: RuntimeID?, ...)` does accept `provider:` and `runtime:` as factory method parameters — THIS IS CORRECT.
- HOWEVER, chaining `.provider(...)` on an `Operation` returned by `Terra.infer()` is NOT possible because `Operation` has no `.provider()` method. The correct way to set provider/runtime at the operation level is to pass them to the factory method, not chain them.

**RECOMMENDED FIX:** The `provider: Terra.ProviderID(...)` and `runtime: Terra.RuntimeID(...)` parameters on `Terra.infer()` itself are correct. Remove any `.provider()` or `.runtime()` chained calls on `Operation` instances.

---

## CRITICAL: `.capture(.includeContent)` — wrong method signature

**Location:** cookbook.md, "Custom Attributes and Capture" (line 222), "Multi-Tenant Privacy" (line 367)

**DOCUMENTED AS:**
```swift
.capture(.includeContent)
```

**ACTUAL API:**
`Operation.capture(_ policy: CapturePolicy)` exists and accepts `CapturePolicy.includeContent`. This IS correct.

However, `CapturePolicy` is defined in `Terra+ComposableAPI.swift` as `Terra.CapturePolicy`. Verify the cookbook examples import the correct module.

**RECOMMENDED FIX:** No change needed if `Terra.CapturePolicy` is imported. However, note that the public API for content capture on an Operation is via `.capture(.includeContent)`, which is what the cookbook shows.

---

## CRITICAL: `.attr(.init("key"), value)` — `TraceAttribute.init` is package-private

**Location:** cookbook.md, Agent Workflow examples (lines 88, 102, 131, 141, 224, 368)

**DOCUMENTED AS:**
```swift
.attr(.init("search.query"), query)
.attr(.init("step.name"), "summarize")
.attr(.init("user.request"), userRequest)
.attr(.init("intent"), intent)
.attr(.init("app.request_id"), UUID().uuidString)
.attr(.init("app.user_tier"), "pro")
.attr(.init("tenant_id"), tenantID)
```

**ACTUAL API:**
- `Terra.TraceAttribute` is `package` (not `public`) in `Terra+ComposableAPI.swift`.
- `Terra.TraceKey` is `package` (not `public`).
- The public API for adding attributes to an `Operation` before `.run()` does not exist via `.attr()`. The `.attr()` method shown in the cookbook is `package static func attr(...)` which is not accessible outside the module.

Additionally, even if accessible, the signature `attr(_ key: TraceKey<Value>, _ value: Value)` requires a `TraceKey` (not a string), and the value must conform to `ScalarValue` (String, Int, Double, Bool).

**RECOMMENDED FIX:**
- Either expose a public `.attr(_ name: String, _ value: Any)` method on `Operation`, OR
- Change cookbook examples to use the `@Terra.MetadataBuilder` result builder pattern inside the `.run()` closure (e.g., `Terra.attr(.init("key"), value)` as a metadata entry before the `.run { trace in ... }` block).

---

## CRITICAL: `.run(using: TestEngine())` — `run(using:)` is package-private, not public

**Location:** cookbook.md, "Engine Injection (Testing)" (lines 472, 512, 559)

**DOCUMENTED AS:**
```swift
.run(using: TestEngine()) { trace in
    trace.event("tool.mocked")
    return "stubbed"
}
```

**ACTUAL API:**
- `Operation.run<R: Sendable, Engine: TelemetryEngine>(using engine: Engine, _ body: ...)` is `package` visibility, NOT `public`. It cannot be called from outside the `Terra` module.
- The public `run()` methods on `Operation` do not accept a `TelemetryEngine` parameter.

**RECOMMENDED FIX:**
- If test engine injection is a supported public feature, make `run(using:engine:_:)` `public` on `Operation`.
- If not intended for public use, remove these cookbook examples or mark them as demonstrating internal API.

---

## CRITICAL: `TelemetryEngine` protocol is package-private

**Location:** cookbook.md, "Engine Injection (Testing)" (lines 455-561)

**DOCUMENTED AS:**
```swift
struct TestEngine: Terra.TelemetryEngine {
    func run<R: Sendable>(
        context: Terra.TelemetryContext,
        attributes: [Terra.TraceAttribute],
        _ body: @escaping @Sendable (Terra.TraceHandle) async throws -> R
    ) async throws -> R { ... }
}
```

**ACTUAL API:**
`Terra.TelemetryEngine` is `package` visibility in `Terra+ComposableAPI.swift`. Users cannot conform to this protocol from outside the module.

**RECOMMENDED FIX:**
- If this is intended to be a public testing API, make `TelemetryEngine` `public`.
- If not, remove or move these examples to internal documentation.

---

## HIGH: `.stream()` missing required `prompt:` parameter in cookbook

**Location:** cookbook.md, "Streaming" section (line 52)

**DOCUMENTED AS:**
```swift
Terra.stream(Terra.ModelID("gpt-4o-mini"), prompt: prompt)
```

**ACTUAL API:**
`Terra.stream(_ model: ModelID, prompt: String?, ...)` — this is CORRECT. The `prompt:` label matches the actual signature.

---

## HIGH: `.embed()` API mismatch

**Location:** cookbook.md, "Embeddings" section (lines 191-194)

**DOCUMENTED AS:**
```swift
Terra.embed(Terra.ModelID("text-embedding-3-small"), inputCount: 1)
    .run { [[0.11, 0.22, 0.33]] }
```

**ACTUAL API:**
- `Terra.embed(_ model: ModelID, inputCount: Int?, provider: ProviderID?, runtime: RuntimeID?) -> Operation` — CORRECT signature.
- `.run { [[0.11, 0.22, 0.33]] }` — The `Operation.run()` takes an async closure. The body returns `[[Double]]` which is valid if the closure is `() async throws -> [[Double]]`. The `run { ... }` shorthand works because of the `@escaping @Sendable () async throws -> R` overload.

**RECOMMENDED FIX:** Verify the closure is marked `async throws` if it performs async work. In this case the body is synchronous so it should work, but the pattern may be misleading.

---

## HIGH: `TerraMLX.traced` example uses wrong parameter order

**Location:** cookbook.md, "MLX" section (lines 436-448)

**DOCUMENTED AS:**
```swift
let text = try await TerraMLX.traced(
    model: Terra.ModelID("mlx-community/Llama-3.2-1B"),
    maxTokens: 256,
    temperature: 0.7,
    device: "ane",
    memoryFootprintMB: 512,
    modelLoadDurationMS: 1800
) {
    TerraMLX.recordFirstToken()
    TerraMLX.recordTokenCount(32)
    return "mlx output"
}
```

**ACTUAL API:**
`TerraMLX.traced<R>(model: Terra.ModelID, maxTokens: Int?, temperature: Double?, device: String?, memoryFootprintMB: Double?, modelLoadDurationMS: Double?, _ body: ...)` — The signature is CORRECT. The trailing closure syntax is also correct.

**RECOMMENDED FIX:** No change needed. The example is correct.

---

## HIGH: `Terra.TracedSession` availability and API

**Location:** cookbook.md, "Foundation Models" section (lines 418-429)

**DOCUMENTED AS:**
```swift
let session = Terra.TracedSession(model: .default)
return try await session.respond(to: prompt)
```

**ACTUAL API:**
- `TerraTracedSession` is `internal` (not `public`) in `TerraTracedSession.swift`.
- `Terra.TracedSession` is not publicly exported from the `Terra` module.
- The `.default` parameter for `model:` accepts `SystemLanguageModel`, which requires `import FoundationModels`.

**RECOMMENDED FIX:**
- Make `TerraTracedSession` `public` if this is a supported public API.
- Change `Terra.TracedSession` to the actual public type name if different.
- Ensure the `SystemLanguageModel.default` usage is correct.

---

## MEDIUM: `.agent("trip-planner", id: "agent-42")` — parameter labels correct

**Location:** cookbook.md, "Agent Workflow" (line 65)

**DOCUMENTED AS:**
```swift
Terra.agent("trip-planner", id: "agent-42")
```

**ACTUAL API:**
`Terra.agent(_ name: String, id: String?, provider: ProviderID?, runtime: RuntimeID?)` — CORRECT.

---

## MEDIUM: `.tool("web-search", callID: Terra.ToolCallID())` — `.tool()` return type has no `.attr()`

**Location:** cookbook.md, "Agent Workflow" (lines 66-94, 129-146)

The `.tool()` API and `.attr()` chaining:
- `Terra.tool(_ name: String, callID: ToolCallID = .init(), ...)` returns `Operation` — CORRECT.
- `Operation.attr()` does not exist as a public method. Only `Terra.attr()` exists as a `package static` method for use within `@Terra.MetadataBuilder`.

**RECOMMENDED FIX:** The `.attr(.init("search.query"), query)` call on `Operation` is invalid. If attribute-setting on Operation before `.run()` is desired, add a public `.attr(_:_:)` method to `Operation`, or change examples to use the `@Terra.MetadataBuilder` pattern.

---

## MEDIUM: `.run { trace in trace.tokens(input: 120, output: 60) }` — `.tokens()` signature mismatch

**Location:** cookbook.md, "Safety Pipeline" (lines 199-209)

**DOCUMENTED AS:**
```swift
Terra.safety("input-moderation", subject: userText)
    .run { true }  // <-- returns Bool directly

Terra.infer(Terra.ModelID("gpt-4o-mini"), prompt: userText)
    .run { "response" }

Terra.safety("output-moderation", subject: answer)
    .run { safe }  // <-- returns Bool
```

**ACTUAL API:**
`Operation.run(_ body: @escaping @Sendable () async throws -> R)` and `run(_ body: @escaping @Sendable (TraceHandle) async throws -> R)` — Both exist. The cookbook closures return values directly, which is valid for the first overload. CORRECT.

---

## MEDIUM: `.run { trace in trace.event("guardrail.decision") }` — closure parameter type

**Location:** cookbook.md, "Error Recording" (lines 234-244)

**DOCUMENTED AS:**
```swift
Terra.infer(Terra.ModelID("gpt-4o-mini"), prompt: "Test")
    .run { trace in
        trace.event("guardrail.decision")
        ...
        return "ok"
    }
```

**ACTUAL API:**
The `Operation.run(_ body: @escaping @Sendable (TraceHandle) async throws -> R)` overload accepts a closure with `TraceHandle`. The cookbook usage is CORRECT.

---

## MEDIUM: `Terra.event(_:)` usage inside `.run { trace in }` — wrong context

**Location:** cookbook.md, "Error Handling Patterns" (lines 249-285)

**DOCUMENTED AS:**
```swift
Terra.infer(Terra.ModelID("gpt-4o-mini"), prompt: prompt)
    .run { trace in
        do {
            return try await llm.generate(prompt)
        } catch {
            trace.recordError(error)
            trace.event("inference.fallback")  // <-- trace.event, not Terra.event
            throw error
        }
    }
```

**ACTUAL API:** `trace.event(_:)` on `TraceHandle` is `public`. This is CORRECT. The cookbook uses `trace.event(...)` not `Terra.event(...)` inside the `.run { trace in }` closure, which is correct.

---

## MEDIUM: `.tag()` vs `.attr()` on TraceHandle — potential confusion

**Location:** cookbook.md, "Conditional Error Handling" (line 276)

**DOCUMENTED AS:**
```swift
trace.tag("error.type", "rate_limit")
```

**ACTUAL API:**
`TraceHandle.tag<T: CustomStringConvertible & Sendable>(_ key: StaticString, _ value: T)` is `public` and exists. This is CORRECT, though `.tag()` stores values as strings (not structured numeric), which is noted in the `TraceHandle.tag` documentation.

---

## Summary of Critical Issues

| # | Severity | Issue | File Location |
|---|----------|-------|---------------|
| 1 | CRITICAL | `.provider()` chaining on `Operation` is invalid (but passing `provider:` to factory method is correct) | Multiple sections |
| 2 | CRITICAL | `.attr(.init(...), value)` — `TraceAttribute`/`TraceKey` are `package`, not `public` | Agent Workflow, Custom Attributes |
| 3 | CRITICAL | `Operation.run(using:)` is `package`, not `public` — test engine injection is not public API | Engine Injection section |
| 4 | CRITICAL | `TelemetryEngine` protocol is `package`, not `public` | Engine Injection section |
| 5 | HIGH | `Terra.TracedSession` is `internal`, not `public` — Foundation Models example will not compile | Foundation Models section |
| 6 | HIGH | `.attr()` on `Operation` does not exist as a public API | Tool examples in Agent Workflow |

## Recommended Actions

1. **Make `TelemetryEngine`, `Operation.run(using:)`, `TraceAttribute`, `TraceKey` public** if test engine injection and attribute-setting on Operation are intended public APIs.
2. **Make `TerraTracedSession` public** if Foundation Models integration is a supported public feature.
3. **Add public `.attr(_:_:)` to `Operation`** or document the `@Terra.MetadataBuilder` pattern as the recommended way to set per-operation attributes.
4. **Fix `.provider()` chaining** in examples — ensure provider/runtime are set via factory method parameters, not chained calls.
5. **Verify `.capture(.includeContent)`** resolves correctly via `Terra.CapturePolicy` import.
