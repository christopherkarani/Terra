# Terra API v3 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rewrite Terra's public API surface for agent-first developer experience: closure-first spans, simplified privacy, expanded macros, Foundation Models drop-in session.

**Architecture:** Bottom-up implementation. Start with privacy and constants (no dependencies), then trace protocol, then closure-first factories, then builder escape hatch, then macros, then Foundation Models. Each phase is independently testable and commitable.

**Tech Stack:** Swift 5.9+, SwiftSyntax 600+, OpenTelemetry Swift Core 2.3+, swift-testing

**Reference:** `docs/plans/2026-03-01-api-v3-design.md` for full API specification.

---

## Phase 1: Privacy Simplification

### Task 1.1: New Privacy Enum

**Files:**
- Create: `Sources/Terra/Terra+PrivacyV3.swift`
- Test: `Tests/TerraTests/TerraPrivacyV3Tests.swift`

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

@Test("Privacy.redacted is the default")
func redactedIsDefault() {
    let config = Terra.Configuration()
    #expect(config.privacy == .redacted)
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
        /// Default. Content hashed with HMAC-SHA256. Privacy-first.
        case redacted
        /// Only capture string lengths. No content or hashes.
        case lengthOnly
        /// Full content capture. Use for development/debugging.
        case capturing
        /// Drop all content. Spans have structure only.
        case silent

        /// Whether this policy captures content by default.
        public var shouldCapture: Bool {
            self == .capturing
        }

        /// Whether content should be captured, considering per-call override.
        public func shouldCapture(includeContent: Bool) -> Bool {
            if self == .silent { return false }
            return includeContent || self == .capturing
        }

        /// The redaction strategy implied by this policy.
        var redactionStrategy: RedactionStrategy {
            switch self {
            case .redacted: return .hashHMACSHA256
            case .lengthOnly: return .lengthOnly
            case .capturing: return .hashHMACSHA256 // Still hash, but also capture raw
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

### Task 1.2: Flattened Configuration Struct

**Files:**
- Create: `Sources/Terra/Terra+ConfigurationV3.swift`
- Test: `Tests/TerraTests/TerraConfigurationV3Tests.swift`

**Step 1: Write the failing test**

```swift
// Tests/TerraTests/TerraConfigurationV3Tests.swift
import Testing
import Foundation
@testable import TerraCore

@Test("Configuration has sensible defaults")
func configurationDefaults() {
    let config = Terra.Configuration()
    #expect(config.privacy == .redacted)
    #expect(config.serviceName == nil)
    #expect(config.samplingRatio == nil)
    #expect(config.metricsInterval == 60)
    #expect(config.enableSignposts == true)
    #expect(config.enableSessions == true)
}

@Test("Preset.quickstart creates correct configuration")
func quickstartPreset() {
    let config = Terra.Configuration(preset: .quickstart)
    #expect(config.privacy == .redacted)
    #expect(config.persistence == nil)
}

@Test("Preset.production enables persistence")
func productionPreset() {
    let config = Terra.Configuration(preset: .production)
    #expect(config.persistence != nil)
}

@Test("Configuration supports builder-style overrides")
func configurationOverrides() {
    var config = Terra.Configuration(preset: .production)
    config.privacy = .capturing
    #expect(config.privacy == .capturing)
    #expect(config.persistence != nil)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter TerraTests.TerraConfigurationV3Tests`
Expected: FAIL — `Terra.Configuration` type not found

**Step 3: Write minimal implementation**

```swift
// Sources/Terra/Terra+ConfigurationV3.swift
import Foundation

extension Terra {
    public enum Preset: Sendable {
        /// Local development. Traces to localhost:4318. No persistence.
        case quickstart
        /// Production. On-device persistence. Privacy-first defaults.
        case production
        /// Full diagnostics: logs, memory/GPU profiling, OpenClaw.
        case diagnostics
    }

    public struct Configuration: Sendable {
        // Essential
        public var privacy: PrivacyPolicy = .redacted
        public var endpoint: URL = URL(string: "http://127.0.0.1:4318")!
        public var serviceName: String? = nil

        // Instruments
        public var instrumentations: Instrumentations = .all

        // Advanced
        public var serviceVersion: String? = nil
        public var anonymizationKey: Data? = nil
        public var samplingRatio: Double? = nil
        public var persistence: PersistenceConfiguration? = nil
        public var metricsInterval: TimeInterval = 60
        public var enableSignposts: Bool = true
        public var enableSessions: Bool = true
        public var resourceAttributes: [String: String] = [:]

        public init() {}

        public init(preset: Preset) {
            switch preset {
            case .quickstart:
                break // defaults are quickstart
            case .production:
                self.persistence = PersistenceConfiguration()
            case .diagnostics:
                self.persistence = PersistenceConfiguration()
                // diagnostics enables additional profiling
            }
        }
    }
}
```

**Step 4: Run tests**

Run: `swift test --filter TerraTests.TerraConfigurationV3Tests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/Terra/Terra+ConfigurationV3.swift Tests/TerraTests/TerraConfigurationV3Tests.swift
git commit -m "feat: add flat Configuration struct with Preset enum"
```

---

## Phase 2: Trace Protocol and Typed Traces

### Task 2.1: Trace Protocol

**Files:**
- Create: `Sources/Terra/Terra+TraceProtocol.swift`
- Test: `Tests/TerraTests/TerraTraceProtocolTests.swift`

**Step 1: Write the failing test**

```swift
// Tests/TerraTests/TerraTraceProtocolTests.swift
import Testing
import OpenTelemetryApi
@testable import TerraCore

@Test("InferenceTrace conforms to Trace protocol")
func inferenceTraceConformsToTrace() {
    let support = TerraTestSupport()
    let tracer = support.tracerProvider.get(instrumentationName: "test")
    let span = tracer.spanBuilder(spanName: "test").startSpan()

    let trace = Terra.InferenceTrace(span: span)
    // Should be able to call protocol methods
    trace.event("test_event")
    trace.attribute("key", "value")
    span.end()

    let spans = support.finishedSpans()
    #expect(spans.count == 1)
    #expect(spans[0].events.contains { $0.name == "test_event" })
}

@Test("InferenceTrace supports typed tokens method")
func inferenceTraceTokens() {
    let support = TerraTestSupport()
    let tracer = support.tracerProvider.get(instrumentationName: "test")
    let span = tracer.spanBuilder(spanName: "test").startSpan()

    let trace = Terra.InferenceTrace(span: span)
    trace.tokens(input: 50, output: 100)
    span.end()

    let spans = support.finishedSpans()
    let attrs = spans[0].attributes
    #expect(attrs["gen_ai.usage.input_tokens"]?.description == "50")
    #expect(attrs["gen_ai.usage.output_tokens"]?.description == "100")
}

@Test("StreamingTrace supports chunk method")
func streamingTraceChunk() {
    let support = TerraTestSupport()
    let tracer = support.tracerProvider.get(instrumentationName: "test")
    let span = tracer.spanBuilder(spanName: "test").startSpan()

    let trace = Terra.StreamingTrace(span: span)
    trace.chunk(tokens: 5)
    trace.chunk(tokens: 3)
    span.end()

    let spans = support.finishedSpans()
    #expect(spans[0].attributes["terra.stream.output_tokens"]?.description == "8")
    #expect(spans[0].attributes["terra.stream.chunk_count"]?.description == "2")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter TerraTests.TerraTraceProtocolTests`
Expected: FAIL — `Trace` protocol not found

**Step 3: Write minimal implementation**

```swift
// Sources/Terra/Terra+TraceProtocol.swift
import OpenTelemetryApi

extension Terra {

    // MARK: - Trace Protocol

    public protocol Trace: Sendable {
        var span: any Span { get }
        @discardableResult func event(_ name: String) -> Self
        @discardableResult func attribute(_ key: String, _ value: String) -> Self
        @discardableResult func attribute(_ key: String, _ value: Int) -> Self
        @discardableResult func attribute(_ key: String, _ value: Double) -> Self
        @discardableResult func attribute(_ key: String, _ value: Bool) -> Self
        func recordError(_ error: any Error)
    }

    // MARK: - InferenceTrace

    public struct InferenceTrace: Trace {
        public let span: any Span

        public init(span: any Span) { self.span = span }

        @discardableResult public func event(_ name: String) -> Self {
            span.addEvent(name: name); return self
        }
        @discardableResult public func attribute(_ key: String, _ value: String) -> Self {
            span.setAttribute(key: key, value: value); return self
        }
        @discardableResult public func attribute(_ key: String, _ value: Int) -> Self {
            span.setAttribute(key: key, value: value); return self
        }
        @discardableResult public func attribute(_ key: String, _ value: Double) -> Self {
            span.setAttribute(key: key, value: value); return self
        }
        @discardableResult public func attribute(_ key: String, _ value: Bool) -> Self {
            span.setAttribute(key: key, value: value); return self
        }
        public func recordError(_ error: any Error) {
            span.addEvent(name: "exception", attributes: [
                "exception.type": .string(String(describing: type(of: error))),
                "exception.message": .string(error.localizedDescription)
            ])
            span.status = .error(description: error.localizedDescription)
        }

        // Inference-specific
        @discardableResult public func tokens(input: Int? = nil, output: Int? = nil) -> Self {
            if let input { span.setAttribute(key: "gen_ai.usage.input_tokens", value: input) }
            if let output { span.setAttribute(key: "gen_ai.usage.output_tokens", value: output) }
            return self
        }
        @discardableResult public func responseModel(_ value: String) -> Self {
            span.setAttribute(key: "gen_ai.response.model", value: value); return self
        }
    }

    // MARK: - StreamingTrace

    public final class StreamingTrace: @unchecked Sendable, Trace {
        public let span: any Span
        private let lock = NSLock()
        private var outputTokenCount: Int = 0
        private var chunkCount: Int = 0
        private var firstChunkTime: ContinuousClock.Instant?
        private let startTime: ContinuousClock.Instant

        public init(span: any Span) {
            self.span = span
            self.startTime = .now
        }

        @discardableResult public func event(_ name: String) -> Self {
            span.addEvent(name: name); return self
        }
        @discardableResult public func attribute(_ key: String, _ value: String) -> Self {
            span.setAttribute(key: key, value: value); return self
        }
        @discardableResult public func attribute(_ key: String, _ value: Int) -> Self {
            span.setAttribute(key: key, value: value); return self
        }
        @discardableResult public func attribute(_ key: String, _ value: Double) -> Self {
            span.setAttribute(key: key, value: value); return self
        }
        @discardableResult public func attribute(_ key: String, _ value: Bool) -> Self {
            span.setAttribute(key: key, value: value); return self
        }
        public func recordError(_ error: any Error) {
            span.addEvent(name: "exception", attributes: [
                "exception.type": .string(String(describing: type(of: error))),
                "exception.message": .string(error.localizedDescription)
            ])
            span.status = .error(description: error.localizedDescription)
        }

        // Streaming-specific
        @discardableResult public func chunk(tokens: Int = 1) -> Self {
            lock.withLock {
                if firstChunkTime == nil { firstChunkTime = .now }
                chunkCount += 1
                outputTokenCount += tokens
            }
            span.setAttribute(key: "terra.stream.output_tokens", value: outputTokenCount)
            span.setAttribute(key: "terra.stream.chunk_count", value: chunkCount)
            return self
        }

        @discardableResult public func outputTokens(_ total: Int) -> Self {
            lock.withLock { outputTokenCount = total }
            span.setAttribute(key: "terra.stream.output_tokens", value: total)
            return self
        }

        @discardableResult public func firstToken() -> Self {
            lock.withLock { if firstChunkTime == nil { firstChunkTime = .now } }
            return self
        }

        func finish() {
            lock.withLock {
                if let ttft = firstChunkTime {
                    let ms = Double(startTime.duration(to: ttft).components.attoseconds) / 1e15
                    span.setAttribute(key: "terra.stream.time_to_first_token_ms", value: ms)
                }
                if outputTokenCount > 0, let ttft = firstChunkTime {
                    let totalSec = Double(ttft.duration(to: .now).components.attoseconds) / 1e18
                    if totalSec > 0 {
                        span.setAttribute(key: "terra.stream.tokens_per_second",
                                          value: Double(outputTokenCount) / totalSec)
                    }
                }
            }
        }
    }

    // MARK: - Simple Traces (protocol only, no extra methods)

    public struct AgentTrace: Trace {
        public let span: any Span
        public init(span: any Span) { self.span = span }
        @discardableResult public func event(_ name: String) -> Self {
            span.addEvent(name: name); return self
        }
        @discardableResult public func attribute(_ key: String, _ value: String) -> Self {
            span.setAttribute(key: key, value: value); return self
        }
        @discardableResult public func attribute(_ key: String, _ value: Int) -> Self {
            span.setAttribute(key: key, value: value); return self
        }
        @discardableResult public func attribute(_ key: String, _ value: Double) -> Self {
            span.setAttribute(key: key, value: value); return self
        }
        @discardableResult public func attribute(_ key: String, _ value: Bool) -> Self {
            span.setAttribute(key: key, value: value); return self
        }
        public func recordError(_ error: any Error) {
            span.addEvent(name: "exception", attributes: [
                "exception.type": .string(String(describing: type(of: error))),
                "exception.message": .string(error.localizedDescription)
            ])
            span.status = .error(description: error.localizedDescription)
        }
    }

    // ToolTrace, EmbeddingTrace, SafetyCheckTrace follow the same pattern as AgentTrace
    public struct ToolTrace: Trace { /* same as AgentTrace */ }
    public struct EmbeddingTrace: Trace { /* same as AgentTrace */ }
    public struct SafetyCheckTrace: Trace { /* same as AgentTrace */ }
}
```

> **Note:** The ToolTrace, EmbeddingTrace, SafetyCheckTrace implementations are identical to AgentTrace. Use copy-paste or a shared base implementation to DRY. Consider a protocol extension with default implementations using the `span` property.

**Step 4: Run tests**

Run: `swift test --filter TerraTests.TerraTraceProtocolTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/Terra/Terra+TraceProtocol.swift Tests/TerraTests/TerraTraceProtocolTests.swift
git commit -m "feat: add Trace protocol with InferenceTrace, StreamingTrace, and simple traces"
```

---

## Phase 3: Closure-First Span Factories

### Task 3.1: Inference and Agent Factories

**Files:**
- Create: `Sources/Terra/Terra+ClosureAPI.swift`
- Test: `Tests/TerraTests/TerraClosureAPITests.swift`

**Step 1: Write the failing test**

```swift
// Tests/TerraTests/TerraClosureAPITests.swift
import Testing
@testable import TerraCore

@Test("Terra.inference creates span with model attribute")
func inferenceCreatesSpan() async throws {
    let support = TerraTestSupport()

    let result = try await Terra.inference(model: "gpt-4") {
        "hello"
    }

    #expect(result == "hello")
    let spans = support.finishedSpans()
    #expect(spans.count == 1)
    #expect(spans[0].name == "gen_ai.inference")
    #expect(spans[0].attributes["gen_ai.request.model"]?.description == "gpt-4")
}

@Test("Terra.inference with trace context allows token recording")
func inferenceWithTraceContext() async throws {
    let support = TerraTestSupport()

    try await Terra.inference(model: "gpt-4") { (trace: Terra.InferenceTrace) in
        trace.tokens(input: 50, output: 100)
    }

    let spans = support.finishedSpans()
    #expect(spans[0].attributes["gen_ai.usage.input_tokens"]?.description == "50")
    #expect(spans[0].attributes["gen_ai.usage.output_tokens"]?.description == "100")
}

@Test("Terra.inference auto-records errors")
func inferenceAutoRecordsErrors() async throws {
    let support = TerraTestSupport()

    do {
        try await Terra.inference(model: "gpt-4") {
            throw TestError.simulated
        }
    } catch {}

    let spans = support.finishedSpans()
    #expect(spans[0].status == .error(description: "simulated"))
    #expect(spans[0].events.contains { $0.name == "exception" })
}

@Test("Terra.inference with metadata parameters")
func inferenceWithMetadata() async throws {
    let support = TerraTestSupport()

    try await Terra.inference(
        model: "gpt-4",
        prompt: "Hello",
        provider: "openai",
        temperature: 0.7
    ) {
        // body
    }

    let spans = support.finishedSpans()
    #expect(spans[0].attributes["gen_ai.provider.name"]?.description == "openai")
    #expect(spans[0].attributes["gen_ai.request.temperature"]?.description == "0.7")
}

@Test("Terra.agent creates agent span with name")
func agentCreatesSpan() async throws {
    let support = TerraTestSupport()

    try await Terra.agent(name: "ResearchAgent") {
        // agent body
    }

    let spans = support.finishedSpans()
    #expect(spans[0].name == "gen_ai.agent")
    #expect(spans[0].attributes["gen_ai.agent.name"]?.description == "ResearchAgent")
}

@Test("Nested spans create parent-child relationships")
func nestedSpansCreateTree() async throws {
    let support = TerraTestSupport()

    try await Terra.agent(name: "MyAgent") {
        try await Terra.inference(model: "gpt-4") {
            // inner body
        }
    }

    let spans = support.finishedSpans()
    #expect(spans.count == 2)
    // The inference span should be a child of the agent span
    let inferenceSpan = spans.first { $0.name == "gen_ai.inference" }!
    let agentSpan = spans.first { $0.name == "gen_ai.agent" }!
    #expect(inferenceSpan.parentSpanId == agentSpan.spanId)
}

enum TestError: Error, CustomStringConvertible {
    case simulated
    var description: String { "simulated" }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter TerraTests.TerraClosureAPITests`
Expected: FAIL — closure-first factory methods not found

**Step 3: Write minimal implementation**

```swift
// Sources/Terra/Terra+ClosureAPI.swift
import OpenTelemetryApi

extension Terra {

    // MARK: - Inference

    /// Trace an LLM inference call.
    ///
    ///     let response = try await Terra.inference(model: "gpt-4") {
    ///         try await llm.generate("Hello")
    ///     }
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
        let tracer = currentTracer()
        let span = tracer.spanBuilder(spanName: SpanNames.inference).startSpan()
        span.setAttribute(key: "gen_ai.operation.name", value: "inference")
        span.setAttribute(key: "gen_ai.request.model", value: model)
        if let prompt { applyPrompt(prompt, to: span) }
        if let provider { span.setAttribute(key: "gen_ai.provider.name", value: provider) }
        if let runtime { span.setAttribute(key: "terra.runtime", value: runtime) }
        if let temperature { span.setAttribute(key: "gen_ai.request.temperature", value: temperature) }
        if let maxOutputTokens { span.setAttribute(key: "gen_ai.request.max_tokens", value: maxOutputTokens) }

        do {
            let result = try await OpenTelemetry.instance.contextProvider
                .withSpan(span) { try await body() }
            span.end()
            return result
        } catch {
            span.addEvent(name: "exception", attributes: [
                "exception.type": .string(String(describing: type(of: error))),
                "exception.message": .string(error.localizedDescription)
            ])
            span.status = .error(description: error.localizedDescription)
            span.end()
            throw error
        }
    }

    /// Trace an LLM inference call with trace context access.
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
        let tracer = currentTracer()
        let span = tracer.spanBuilder(spanName: SpanNames.inference).startSpan()
        span.setAttribute(key: "gen_ai.operation.name", value: "inference")
        span.setAttribute(key: "gen_ai.request.model", value: model)
        if let prompt { applyPrompt(prompt, to: span) }
        if let provider { span.setAttribute(key: "gen_ai.provider.name", value: provider) }
        if let runtime { span.setAttribute(key: "terra.runtime", value: runtime) }
        if let temperature { span.setAttribute(key: "gen_ai.request.temperature", value: temperature) }
        if let maxOutputTokens { span.setAttribute(key: "gen_ai.request.max_tokens", value: maxOutputTokens) }

        let trace = InferenceTrace(span: span)
        do {
            let result = try await OpenTelemetry.instance.contextProvider
                .withSpan(span) { try await body(trace) }
            span.end()
            return result
        } catch {
            trace.recordError(error)
            span.end()
            throw error
        }
    }

    // MARK: - Agent

    /// Trace an agent invocation.
    @discardableResult
    public static func agent<R>(
        name: String,
        id: String? = nil,
        provider: String? = nil,
        _ body: @Sendable () async throws -> R
    ) async rethrows -> R {
        let tracer = currentTracer()
        let span = tracer.spanBuilder(spanName: SpanNames.agentInvocation).startSpan()
        span.setAttribute(key: "gen_ai.operation.name", value: "invoke_agent")
        span.setAttribute(key: "gen_ai.agent.name", value: name)
        if let id { span.setAttribute(key: "gen_ai.agent.id", value: id) }
        if let provider { span.setAttribute(key: "gen_ai.provider.name", value: provider) }

        do {
            let result = try await OpenTelemetry.instance.contextProvider
                .withSpan(span) { try await body() }
            span.end()
            return result
        } catch {
            span.addEvent(name: "exception", attributes: [
                "exception.type": .string(String(describing: type(of: error))),
                "exception.message": .string(error.localizedDescription)
            ])
            span.status = .error(description: error.localizedDescription)
            span.end()
            throw error
        }
    }

    // MARK: - Helpers

    private static func currentTracer() -> any TracerBuilder {
        OpenTelemetry.instance.tracerProvider
            .get(instrumentationName: instrumentationName,
                 instrumentationVersion: instrumentationVersion)
    }

    private static func applyPrompt(_ prompt: String, to span: any Span) {
        // Respect privacy policy — implementation delegates to runtime privacy config
        span.setAttribute(key: "terra.prompt.length", value: prompt.count)
    }
}
```

> **Note:** Implement remaining factories (stream, tool, embedding, safetyCheck) following the same pattern. Each is a straightforward copy with different span name, operation name, and attribute keys.

**Step 4: Run tests**

Run: `swift test --filter TerraTests.TerraClosureAPITests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/Terra/Terra+ClosureAPI.swift Tests/TerraTests/TerraClosureAPITests.swift
git commit -m "feat: add closure-first inference and agent factories with auto error recording"
```

---

### Task 3.2: Remaining Factories (stream, tool, embedding, safetyCheck)

**Files:**
- Modify: `Sources/Terra/Terra+ClosureAPI.swift`
- Test: `Tests/TerraTests/TerraClosureAPITests.swift` (add more tests)

Follow the same pattern as Task 3.1 for each factory. Key differences:

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

**Step 1:** Rename `.run {}` to `.execute {}` on all Call types (InferenceCall, StreamingCall, etc.)

**Step 2:** Update fluent builders to delegate to closure-first factories instead of internal `withSpan` methods.

**Step 3:** Add `.includeContent()` method replacing `.capture(CaptureIntent)`.

**Step 4:** Run existing fluent API tests (updated for new method names).

**Commit:**
```bash
git commit -m "refactor: rename .run to .execute, add .includeContent on builders"
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
                do {
                    return try await doResearch(topic)
                } catch {
                    trace.recordError(error)
                    throw error
                }
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
                do {
                    return try await doSearch(query)
                } catch {
                    trace.recordError(error)
                    throw error
                }
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

All expansions now include do-catch for error recording.

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
public protocol TerraTraceable {
    var terraTokenUsage: Terra.TokenUsage? { get }
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

Test: Verify that `Terra.inference()` inside `Terra.agent()` registers with the agent context.

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

> **Note:** Foundation Models tests require macOS 26+ simulator. Use `#if canImport(FoundationModels)` guards.

**Commit:**
```bash
git commit -m "feat: rewrite Terra.Session with transcript inspection and guardrail capture"
```

---

## Phase 10: Cleanup and Migration

### Task 10.1: Deprecate V1 API

**Files:**
- Modify: `Sources/Terra/Terra.swift`

Mark all `withSpan` methods as `@available(*, deprecated, renamed:)` pointing to v3 equivalents.

**Commit:**
```bash
git commit -m "chore: deprecate v1 withSpan methods in favor of v3 closure-first API"
```

### Task 10.2: Update Examples

**Files:**
- Modify: `Examples/Terra Sample/main.swift`
- Modify: `Examples/Terra AutoInstrument/main.swift`

Rewrite examples using v3 API patterns.

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

**Commit:**
```bash
git commit -m "fix: resolve test regressions from v3 API migration"
```

---

## Phase Summary

| Phase | Tasks | Estimated Effort |
|-------|-------|-----------------|
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
| **Total** | **17 tasks** | |

---

## Deferred (Future Work)

These items are designed but deferred from this implementation:

- `@TerraAgent` class-level macro with `@Step`, `@Tool`, `@Model` markers
- `@Traced` on class/struct level (instruments all async methods)
- `#trace` expression macro (pending Swift 6.2 trailing closure verification)
- `#instrument` metrics-only macro
- `@TerraTraceable` auto-conformance macro
- Span links for inference→tool relationships (`.linkedTo()`)
