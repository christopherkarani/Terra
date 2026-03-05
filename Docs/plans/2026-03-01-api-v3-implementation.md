# Terra API v3 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rewrite Terra's public API surface for agent-first developer experience: closure-first spans, simplified privacy, expanded macros, Foundation Models drop-in session.

**Architecture:** Migration-safe bottom-up implementation. Start with build guardrails and compatibility policy, then privacy/config foundations, trace protocol extraction, closure-first overloads, builder terminal migration, macros, and Foundation Models. Keep package builds green at every phase boundary.

**Tech Stack:** Swift 5.9+, SwiftSyntax 600+, OpenTelemetry Swift Core 2.3+, swift-testing

**Reference:** `docs/plans/2026-03-01-api-v3-design.md` for full API specification.

---

## Phase 0: Migration Safety Guardrails

### Task 0.1: Make New `TerraTests` Macros Compile

**Files:**
- Modify: `Package.swift`

Add `.product(name: "Testing", package: "swift-testing")` to the `TerraTests` target dependencies before adding any new `import Testing` tests in that target.

**Commit:**
```bash
git add Package.swift
git commit -m "build: add swift-testing dependency to TerraTests target"
```

### Task 0.2: Compatibility Window Policy

Before API renames, define rollout rules in this plan and follow them in code:
1. Add new API first.
2. Keep old API as deprecated forwarders.
3. Migrate internal call sites (all targets + tests + examples + macros).
4. Remove deprecated API only in a later major release.

---

## Phase 1: Privacy Simplification

### Task 1.1: New Privacy Enum

**Files:**
- Create: `Sources/Terra/Terra+PrivacyV3.swift`
- Test: `Tests/TerraTests/TerraPrivacyV3Tests.swift`

**Important sequencing note:** this task must not reference `Terra.Configuration`; configuration is introduced in Task 1.2.

**Step 1: Write the failing test**

```swift
// Tests/TerraTests/TerraPrivacyV3Tests.swift
import Testing
@testable import TerraCore

@Test("Privacy enum has four cases")
func privacyEnumCases() {
    let policies: [Terra.PrivacyPolicy] = [.redacted, .lengthOnly, .capturing, .silent]
    #expect(policies.count == 4)
}

@Test("Privacy.shouldCapture returns correct values")
func shouldCaptureLogic() {
    #expect(Terra.PrivacyPolicy.redacted.shouldCapture == false)
    #expect(Terra.PrivacyPolicy.lengthOnly.shouldCapture == false)
    #expect(Terra.PrivacyPolicy.capturing.shouldCapture == true)
    #expect(Terra.PrivacyPolicy.silent.shouldCapture == false)
}

@Test("Privacy.shouldCapture with includeContent override")
func includeContentOverride() {
    #expect(Terra.PrivacyPolicy.redacted.shouldCapture(includeContent: true) == true)
    #expect(Terra.PrivacyPolicy.silent.shouldCapture(includeContent: true) == false)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter TerraTests.TerraPrivacyV3Tests`
Expected: FAIL — `PrivacyPolicy` type not found

**Step 3: Write minimal implementation**

```swift
// Sources/Terra/Terra+PrivacyV3.swift
extension Terra {
    public enum PrivacyPolicy: String, Sendable, Hashable {
        case redacted
        case lengthOnly
        case capturing
        case silent

        public var shouldCapture: Bool { self == .capturing }

        public func shouldCapture(includeContent: Bool) -> Bool {
            if self == .silent { return false }
            return includeContent || self == .capturing
        }

        var redactionStrategy: RedactionStrategy {
            switch self {
            case .redacted: return .hashHMACSHA256
            case .lengthOnly: return .lengthOnly
            case .capturing: return .hashHMACSHA256
            case .silent: return .drop
            }
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter TerraTests.TerraPrivacyV3Tests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/Terra/Terra+PrivacyV3.swift Tests/TerraTests/TerraPrivacyV3Tests.swift
git commit -m "feat: add PrivacyPolicy enum for v3 simplified privacy"
```

---

### Task 1.2: Flattened Configuration Struct (Terra Target, No Cross-Module Collision)

**Files:**
- Modify: `Sources/TerraAutoInstrument/Terra+Start.swift`
- Test: `Tests/TerraAutoInstrumentTests/TerraConfigurationV3Tests.swift`

**Rationale:** `Instrumentations` and `start(...)` live in the `Terra` target, so v3 setup configuration must be introduced there first. Do not add another `Terra.Configuration` in `TerraCore`.

**Step 1: Write the failing test**

```swift
// Tests/TerraAutoInstrumentTests/TerraConfigurationV3Tests.swift
import Testing
import Terra

@Test("V3Configuration has sensible defaults")
func configurationDefaults() {
    let config = Terra.V3Configuration()
    #expect(config.privacy == .redacted)
    #expect(config.serviceName == nil)
    #expect(config.samplingRatio == nil)
    #expect(config.metricsInterval == 60)
    #expect(config.enableSignposts == true)
    #expect(config.enableSessions == true)
}

@Test("Preset.quickstart creates correct configuration")
func quickstartPreset() {
    let config = Terra.V3Configuration(preset: .quickstart)
    #expect(config.privacy == .redacted)
    #expect(config.persistence == nil)
}

@Test("Preset.production enables persistence")
func productionPreset() {
    let config = Terra.V3Configuration(preset: .production)
    #expect(config.persistence != nil)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter TerraAutoInstrumentTests.TerraConfigurationV3Tests`
Expected: FAIL — `Terra.V3Configuration` type not found

**Step 3: Write minimal implementation**

```swift
// Sources/TerraAutoInstrument/Terra+Start.swift
extension Terra {
    public struct V3Configuration: Sendable {
        public var privacy: Terra.PrivacyPolicy = .redacted
        public var endpoint: URL = .init(string: "http://127.0.0.1:4318")!
        public var serviceName: String? = nil
        public var instrumentations: Instrumentations = .all
        public var serviceVersion: String? = nil
        public var anonymizationKey: Data? = nil
        public var samplingRatio: Double? = nil
        public var persistence: PersistenceConfiguration? = nil
        public var metricsInterval: TimeInterval = 60
        public var enableSignposts: Bool = true
        public var enableSessions: Bool = true
        public var resourceAttributes: [String: String] = [:]

        public init(preset: Preset = .quickstart) { /* map presets */ }
    }
}
```

**Step 4: Run tests**

Run: `swift test --filter TerraAutoInstrumentTests.TerraConfigurationV3Tests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/TerraAutoInstrument/Terra+Start.swift Tests/TerraAutoInstrumentTests/TerraConfigurationV3Tests.swift
git commit -m "feat: add v3 setup configuration in Terra target"
```

---

## Phase 2: Trace Protocol and Typed Traces

### Task 2.1: Trace Protocol

**Files:**
- Create: `Sources/Terra/Terra+TraceProtocol.swift`
- Modify: `Sources/Terra/Terra+FluentAPI.swift`
- Test: `Tests/TerraTests/TerraTraceProtocolTests.swift`

**Implementation rules (must-follow):**
1. Do not redeclare `InferenceTrace`, `StreamingTrace`, `AgentTrace`, `ToolTrace`, `EmbeddingTrace`, or `SafetyCheckTrace`.
2. Move existing trace type declarations out of `Terra+FluentAPI.swift` into `Terra+TraceProtocol.swift`, then make them conform to `Trace`.
3. Keep behavior identical while extracting (no semantic changes in this task).

**Step 1: Write the failing test**

Add tests that validate conformance and existing behavior (events/attributes/tokens/chunk accounting), but instantiate traces through existing runtime paths rather than inventing new constructors.

**Step 2: Run test to verify it fails**

Run: `swift test --filter TerraTests.TerraTraceProtocolTests`
Expected: FAIL — `Trace` protocol conformance not yet wired

**Step 3: Implement**

```swift
// Sources/Terra/Terra+TraceProtocol.swift
import OpenTelemetryApi

extension Terra {
    public protocol Trace: Sendable {
        @discardableResult func event(_ name: String) -> Self
        @discardableResult func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self
        @discardableResult func emit<E: TerraEvent>(_ event: E) -> Self
        func recordError(_ error: any Error)
    }
}
```

Then:
1. Move existing trace types from `Terra+FluentAPI.swift` into this file.
2. Add `recordError(_:)` to each trace type by delegating to underlying scope behavior.
3. Delete moved declarations from the original file to avoid duplicate symbol errors.

**Step 4: Run tests**

Run: `swift test --filter TerraTests.TerraTraceProtocolTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/Terra/Terra+TraceProtocol.swift Sources/Terra/Terra+FluentAPI.swift Tests/TerraTests/TerraTraceProtocolTests.swift
git commit -m "feat: introduce Trace protocol by extracting existing trace types"
```

---

## Phase 3: Closure-First Span Factories

### Task 3.1: Inference and Agent Factories

**Files:**
- Modify: `Sources/Terra/Terra+FluentAPI.swift`
- Test: `Tests/TerraTests/TerraClosureAPITests.swift`

**Step 1: Write failing tests**

Add tests for both overloads of `inference` and `agent`:
1. No-trace closure overload.
2. Trace-parameter overload.
3. Parent-child nesting correctness.
4. Cancellation behavior (`CancellationError` is rethrown and not recorded as failure).

**Step 2: Run test to verify it fails**

Run: `swift test --filter TerraTests.TerraClosureAPITests`
Expected: FAIL — closure-first overloads not found

**Step 3: Implement via delegation (do not reimplement raw OTel plumbing)**

```swift
// Sources/Terra/Terra+FluentAPI.swift
extension Terra {
    @discardableResult
    public static func inference<R>(
        model: String,
        prompt: String? = nil,
        provider: String? = nil,
        runtime: String? = nil,
        temperature: Double? = nil,
        maxOutputTokens: Int? = nil,
        _ body: @Sendable () async throws -> R
    ) async rethrows -> R {
        try await inference(
            model: model,
            prompt: prompt,
            provider: provider,
            runtime: runtime,
            temperature: temperature,
            maxOutputTokens: maxOutputTokens
        ) { _ in
            try await body()
        }
    }

    @discardableResult
    public static func inference<R>(
        model: String,
        prompt: String? = nil,
        provider: String? = nil,
        runtime: String? = nil,
        temperature: Double? = nil,
        maxOutputTokens: Int? = nil,
        _ body: @Sendable (InferenceTrace) async throws -> R
    ) async rethrows -> R {
        var call = inference(model: model, prompt: prompt)
        if let provider { call = call.provider(provider) }
        if let runtime { call = call.runtime(runtime) }
        if let temperature { call = call.temperature(temperature) }
        if let maxOutputTokens { call = call.maxOutputTokens(maxOutputTokens) }
        return try await call.run(body)
    }
}
```

Apply the same delegation pattern for `agent` overloads. This preserves existing privacy redaction, metrics, enrichment attributes, and `CancellationError` handling.
Phase 5 will introduce `.execute` and keep `.run` as a deprecated forwarder.

**Step 4: Run tests**

Run: `swift test --filter TerraTests.TerraClosureAPITests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/Terra/Terra+FluentAPI.swift Tests/TerraTests/TerraClosureAPITests.swift
git commit -m "feat: add closure-first inference and agent factories"
```

---

### Task 3.2: Remaining Factories (stream, tool, embedding, safetyCheck)

**Files:**
- Modify: `Sources/Terra/Terra+FluentAPI.swift`
- Test: `Tests/TerraTests/TerraClosureAPITests.swift` (add more tests)

Follow the same delegation pattern as Task 3.1 for each factory. Key differences:

| Factory | Span name | Operation name | Required params | Trace type |
|---------|-----------|---------------|----------------|------------|
| `stream` | `gen_ai.inference` | `inference` | `model` | `StreamingTrace` |
| `tool` | `gen_ai.tool` | `execute_tool` | `name`, `callID` | `ToolTrace` |
| `embedding` | `gen_ai.embeddings` | `embeddings` | `model` | `EmbeddingTrace` |
| `safetyCheck` | `terra.safety_check` | `safety_check` | `name` | `SafetyCheckTrace` |

**Tests to write for each:**
1. Creates span with correct name and attributes
2. Auto-records errors
3. Returns body result
4. With trace context overload
5. Cancellation is not marked as span failure

**Commit after each factory is green:**
```bash
git commit -m "feat: add stream/tool/embedding/safetyCheck closure-first factories"
```

---

## Phase 4: Flattened Constants

### Task 4.1: Terra.Key Typed Attribute Keys

**Files:**
- Create: `Sources/Terra/Terra+KeyV3.swift`
- Test: `Tests/TerraTests/TerraKeyV3Tests.swift`

**Step 1: Write the failing test**

```swift
@Test("Terra.Key.model has correct OTel name")
func keyModelName() {
    #expect(Terra.Key.model.name == "gen_ai.request.model")
}

@Test("Terra.Key.inputTokens has correct OTel name")
func keyInputTokens() {
    #expect(Terra.Key.inputTokens.name == "gen_ai.usage.input_tokens")
}
```

**Step 3: Write minimal implementation**

```swift
// Sources/Terra/Terra+KeyV3.swift
extension Terra {
    public enum Key {
        public static let model = AttributeKey<String>("gen_ai.request.model")
        public static let responseModel = AttributeKey<String>("gen_ai.response.model")
        public static let maxTokens = AttributeKey<Int>("gen_ai.request.max_tokens")
        public static let temperature = AttributeKey<Double>("gen_ai.request.temperature")
        public static let inputTokens = AttributeKey<Int>("gen_ai.usage.input_tokens")
        public static let outputTokens = AttributeKey<Int>("gen_ai.usage.output_tokens")
        public static let provider = AttributeKey<String>("gen_ai.provider.name")
        public static let runtime = AttributeKey<String>("terra.runtime")
        public static let agentName = AttributeKey<String>("gen_ai.agent.name")
        public static let toolName = AttributeKey<String>("gen_ai.tool.name")
        public static let timeToFirstToken = AttributeKey<Double>("terra.stream.time_to_first_token_ms")
        public static let tokensPerSecond = AttributeKey<Double>("terra.stream.tokens_per_second")
        public static let contentPolicy = AttributeKey<String>("terra.privacy.content_policy")
    }
}
```

**Step 4: Compatibility aliases**

Keep existing `Terra.Keys.*` available during migration. Add deprecated aliases from old constants to `Terra.Key.*` as needed so external and internal call sites do not break in the same release.

**Commit:**
```bash
git commit -m "feat: add flattened Terra.Key typed attribute constants"
```

---

## Phase 5: Builder Escape Hatch

### Task 5.1: Refactor FluentAPI to use .execute{} terminal

**Files:**
- Modify: `Sources/Terra/Terra+FluentAPI.swift`
- Modify: `Tests/TerraTests/TerraFluentAPITests.swift`
- Modify: `Sources/TerraFoundationModels/TerraTracedSession.swift`
- Modify: `Sources/TerraMLX/TerraMLX.swift`
- Modify: `Sources/TerraLlama/TerraLlama.swift`
- Modify: `Sources/TerraTracedMacroPlugin/TracedMacro.swift`
- Modify: `Tests/TerraTracedMacroTests/TracedMacroExpansionTests.swift`

**Step 1:** Add `.execute {}` on all Call types (InferenceCall, StreamingCall, etc.) as the new preferred terminal.

**Step 2:** Keep `.run {}` as a deprecated forwarder to `.execute {}` for migration safety.

**Step 3:** Add `.includeContent()` and keep `.capture(CaptureIntent)` as a deprecated compatibility wrapper.

**Step 4:** Migrate all internal call sites to `.execute {}` (core targets, macros, examples, tests). No mixed-state commits.

**Step 5:** Run fluent API + macro + module tests after migration.

**Commit:**
```bash
git commit -m "refactor: add .execute terminal and compatibility shims for .run/.capture"
```

---

## Phase 6: Macro Expansion — Multi-Span Types

### Task 6.1: Add Agent/Tool/Embedding/Safety Macro Overloads

**Files:**
- Modify: `Sources/TerraTracedMacro/Traced.swift`
- Modify: `Sources/TerraTracedMacroPlugin/TracedMacro.swift`
- Test: `Tests/TerraTracedMacroTests/TracedMacroExpansionTests.swift`

**Step 1: Write failing tests for new macro overloads**

```swift
@Test("@Traced(agent:) expands to Terra.agent(...)")
func agentMacroExpansion() {
    assertMacroExpansion(
        """
        @Traced(agent: "ResearchAgent")
        func research(topic: String) async throws -> Report {
            try await doResearch(topic)
        }
        """,
        expandedSource: """
        func research(topic: String) async throws -> Report {
            return try await Terra.agent(name: "ResearchAgent") { trace in
                return try await doResearch(topic)
            }
        }
        """,
        macros: testMacros
    )
}

@Test("@Traced(tool:) expands with auto callID")
func toolMacroExpansion() {
    assertMacroExpansion(
        """
        @Traced(tool: "search")
        func search(query: String) async throws -> [Result] {
            try await doSearch(query)
        }
        """,
        expandedSource: """
        func search(query: String) async throws -> [Result] {
            return try await Terra.tool(name: "search", callID: UUID().uuidString) { trace in
                return try await doSearch(query)
            }
        }
        """,
        macros: testMacros
    )
}
```

**Step 2: Add macro declarations**

```swift
// Sources/TerraTracedMacro/Traced.swift — add overloads:
@attached(body) public macro Traced(agent: String, id: String? = nil) = #externalMacro(...)
@attached(body) public macro Traced(tool: String, type: String? = nil) = #externalMacro(...)
@attached(body) public macro Traced(embedding: String) = #externalMacro(...)
@attached(body) public macro Traced(safety: String) = #externalMacro(...)
```

**Step 3: Update TracedMacro.swift expansion logic**

Inspect the first argument label to determine span type:
- `model:` → `Terra.inference(...)`
- `agent:` → `Terra.agent(...)`
- `tool:` → `Terra.tool(name:, callID: UUID().uuidString)`
- `embedding:` → `Terra.embedding(...)`
- `safety:` → `Terra.safetyCheck(...)`

**Important:** Macro expansions must NOT add their own do-catch error recording when targeting closure-first factories. Factories already record errors; double wrapping duplicates exception telemetry.

**Commit:**
```bash
git commit -m "feat: expand @Traced macro to support agent, tool, embedding, safety span types"
```

---

### Task 6.2: Enhanced Parameter Detection

**Files:**
- Modify: `Sources/TerraTracedMacroPlugin/TracedMacro.swift`
- Test: `Tests/TerraTracedMacroTests/TracedMacroExpansionTests.swift`

Add detection for: `temperature`, `provider`, `message`, `subject`, `stream` Bool.
Also preserve current aliases (`prompt`, `input`, `query`, `text`, `maxTokens`, `maxOutputTokens`, `max_tokens`).

**Commit:**
```bash
git commit -m "feat: expand @Traced parameter auto-detection (temperature, provider, stream flag)"
```

---

### Task 6.3: Streaming Macro Support

**Files:**
- Modify: `Sources/TerraTracedMacro/Traced.swift`
- Modify: `Sources/TerraTracedMacroPlugin/TracedMacro.swift`
- Test: `Tests/TerraTracedMacroTests/TracedMacroExpansionTests.swift`

Add `@Traced(model: "gpt-4", streaming: true)` that expands to `Terra.stream(...)`.

**Commit:**
```bash
git commit -m "feat: add streaming macro support via @Traced(model:, streaming: true)"
```

---

## Phase 7: TerraTraceable Protocol

### Task 7.1: Protocol and Auto-Extraction

**Files:**
- Create: `Sources/Terra/TerraTraceable.swift`
- Test: `Tests/TerraTests/TerraTraceableTests.swift`

```swift
extension Terra {
    public protocol TerraTraceable {
        var terraTokenUsage: TokenUsage? { get }
        var terraResponseModel: String? { get }
    }

    public struct TokenUsage: Sendable {
        public var input: Int?
        public var output: Int?
        public init(input: Int? = nil, output: Int? = nil) {
            self.input = input
            self.output = output
        }
    }
}
```

Test: Verify that when a `TerraTraceable` return value comes back from `Terra.inference { }`, tokens are auto-extracted.

**Commit:**
```bash
git commit -m "feat: add TerraTraceable protocol for auto token extraction"
```

---

## Phase 8: Agent Context Accumulation

### Task 8.1: Task-Local AgentContext

**Files:**
- Create: `Sources/Terra/Terra+AgentContext.swift`
- Test: `Tests/TerraTests/TerraAgentContextTests.swift`

```swift
import Foundation

extension Terra {
    @TaskLocal static var agentContext: AgentContext?

    final class AgentContext: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var toolsUsed: Set<String> = []
        private(set) var modelsUsed: Set<String> = []
        private(set) var inferenceCount: Int = 0
        private(set) var toolCallCount: Int = 0

        func recordTool(_ name: String) {
            lock.withLock { toolsUsed.insert(name); toolCallCount += 1 }
        }
        func recordModel(_ name: String) {
            lock.withLock { modelsUsed.insert(name); inferenceCount += 1 }
        }
    }
}
```

Tests:
1. `Terra.inference()` inside `Terra.agent()` registers with agent context.
2. Child `Task {}` inherits context.
3. `Task.detached` does not inherit context (explicitly document this behavior).

**Commit:**
```bash
git commit -m "feat: add task-local AgentContext for agent tree metadata accumulation"
```

---

## Phase 9: Foundation Models Integration

### Task 9.1: Terra.Session Drop-In

**Files:**
- Modify: `Sources/TerraFoundationModels/TerraTracedSession.swift`
- Test: `Tests/TerraFoundationModelsTests/TerraTracedSessionTests.swift`

Rewrite `TerraTracedSession` to use the new closure-first API and add:
- Transcript diff inspection for tool calls
- GenerationOptions capture
- Guardrail violation as safety check spans
- Structured output type name tracking
- Streaming field completion events

Migration note: complete this while `.run` compatibility forwarders still exist, then switch to `.execute` in the same phase commit.

> **Note:** Foundation Models tests require macOS 26+ simulator. Use `#if canImport(FoundationModels)` guards.

**Commit:**
```bash
git commit -m "feat: rewrite Terra.Session with transcript inspection and guardrail capture"
```

---

## Phase 10: Cleanup and Migration

### Task 10.1: Deprecate Legacy APIs with Forwarders (No Hard Break)

**Files:**
- Modify: `Sources/Terra/Terra.swift`
- Modify: `Sources/Terra/Terra+FluentAPI.swift`
- Modify: `Sources/TerraAutoInstrument/Terra+Start.swift`
- Modify: `Sources/Terra/Terra+Privacy.swift`

Mark legacy entry points as deprecated forwarders:
1. `with*Span` helpers.
2. `.run {}` terminal (forward to `.execute {}`).
3. `.capture(CaptureIntent)` (forward to `.includeContent()`).
4. Old startup wrappers (`enable/configure`) pointing to `start`.
5. Legacy privacy knobs that are replaced by v3 policy API.

**Commit:**
```bash
git commit -m "chore: add deprecation forwarders for legacy APIs during v3 migration"
```

### Task 10.2: Update Examples

**Files:**
- Modify: `Examples/Terra Sample/main.swift`
- Modify: `Examples/Terra AutoInstrument/main.swift`

Rewrite examples using v3 API patterns (`.execute`, closure-first factories, `start`).

**Commit:**
```bash
git commit -m "docs: update examples to v3 closure-first API"
```

### Task 10.3: Update README

**Files:**
- Modify: `README.md`

Update code snippets to v3 API. Ensure the 3-line hello world is prominent:
```swift
try Terra.start()
let result = try await Terra.inference(model: "gpt-4") { try await llm.generate("Hello") }
```

**Commit:**
```bash
git commit -m "docs: update README with v3 API examples"
```

### Task 10.4: Run Full Test Suite

Run: `swift test`
Expected: ALL tests pass

Fix any regressions from the refactor.

Additionally run targeted sweeps before full suite:
1. `rg -n "\\.run\\s*\\{" Sources Tests Examples` should only show deprecated shim implementations (or intentionally retained docs).
2. `rg -n "capture\\(\\.optIn|capture\\(" Sources Tests Examples` should only show deprecated compatibility coverage.

**Commit:**
```bash
git commit -m "fix: resolve test regressions from v3 API migration"
```

---

## Phase Summary

| Phase | Tasks | Estimated Effort |
|-------|-------|-----------------|
| 0. Migration Guardrails | 2 tasks | Small |
| 1. Privacy | 2 tasks | Small |
| 2. Trace Protocol | 1 task | Medium |
| 3. Closure-First Factories | 2 tasks | Medium |
| 4. Flattened Constants | 1 task | Small |
| 5. Builder Escape Hatch | 1 task | Medium |
| 6. Macro Expansion | 3 tasks | Large |
| 7. TerraTraceable | 1 task | Small |
| 8. Agent Context | 1 task | Medium |
| 9. Foundation Models | 1 task | Large |
| 10. Cleanup | 4 tasks | Medium |
| **Total** | **19 tasks** | |

---

## Deferred (Future Work)

These items are designed but deferred from this implementation:

- `@TerraAgent` class-level macro with `@Step`, `@Tool`, `@Model` markers
- `@Traced` on class/struct level (instruments all async methods)
- `#trace` expression macro (pending Swift 6.2 trailing closure verification)
- `#instrument` metrics-only macro
- `@TerraTraceable` auto-conformance macro
- Span links for inference→tool relationships (`.linkedTo()`)
# Historical Plan Note

This implementation plan is retained for historical context and may reference legacy APIs.
For the current public API, use `Docs/Front_Facing_API.md` and `Docs/Migration_Guide.md`.
