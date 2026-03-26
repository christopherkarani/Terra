# Terra Public API Inventory

This document is a historical inventory snapshot. The current source and DocC bundle are the source of truth; treat this file as reference material that may lag behind the implementation.

---

## Typed IDs

### Terra.ModelID
A unique identifier for a GenAI model (e.g., 'gpt-4o-mini', 'claude-3-sonnet').

```swift
public struct ModelID: Codable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String)
}
```

### Terra.ProviderID
Identifies the AI provider (e.g., OpenAI, Anthropic, Google).

```swift
public struct ProviderID: Codable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String)
}
```

### Terra.RuntimeID
Identifies the runtime backend used for model execution (e.g., `http_api`, `coreml`, `mlx`, `ane`).

```swift
public struct RuntimeID: Codable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String)
}
```

### Terra.ToolCallID
A unique identifier for a tool call within an agentic workflow.

```swift
public struct ToolCallID: Codable, Hashable, Sendable {
    public let rawValue: String

    /// Creates a new ToolCallID with a randomly generated UUID.
    public init()

    /// Creates a new ToolCallID with the given string value.
    public init(_ rawValue: String)
}
```

---

## Operation Factory Methods

### Terra.infer(_:prompt:provider:runtime:temperature:maxTokens:)
Creates an inference operation for a non-streaming model call.

```swift
public static func infer(
    _ model: ModelID,
    prompt: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil,
    temperature: Double? = nil,
    maxTokens: Int? = nil
) -> Operation
```

### Terra.stream(_:prompt:provider:runtime:temperature:maxTokens:expectedTokens:)
Creates a streaming inference operation for a model call with token-by-token streaming.

```swift
public static func stream(
    _ model: ModelID,
    prompt: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil,
    temperature: Double? = nil,
    maxTokens: Int? = nil,
    expectedTokens: Int? = nil
) -> Operation
```

### Terra.embed(_:inputCount:provider:runtime:)
Creates an embedding operation for generating vector representations of text.

```swift
public static func embed(
    _ model: ModelID,
    inputCount: Int? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil
) -> Operation
```

### Terra.agent(_:id:provider:runtime:)
Creates an agent operation representing an autonomous agentic loop.

```swift
public static func agent(
    _ name: String,
    id: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil
) -> Operation
```

### Terra.tool(_:callID:type:provider:runtime:)
Creates a tool-call operation representing a single tool invocation within an agentic workflow.

```swift
public static func tool(
    _ name: String,
    callID: ToolCallID = .init(),
    type: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil
) -> Operation
```

### Terra.safety(_:subject:provider:runtime:)
Creates a safety-evaluation operation representing a content safety check.

```swift
public static func safety(
    _ name: String,
    subject: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil
) -> Operation
```

---

## Operation Methods

### Operation.capture(_:)
Overrides the capture policy for this operation.

```swift
public func capture(_ policy: CapturePolicy) -> Self
```

### Operation.run(_:) async
Executes the operation, ignoring the trace handle.

```swift
@discardableResult
public func run<R: Sendable>(
    _ body: @escaping @Sendable () async throws -> R
) async rethrows -> R
```

### Operation.run(_:(TraceHandle) async throws -> R) async rethrows -> R
Executes the operation with a trace handle.

```swift
@discardableResult
public func run<R: Sendable>(
    _ body: @escaping @Sendable (TraceHandle) async throws -> R
) async rethrows -> R
```

---

## TraceHandle Methods

A handle for adding events, attributes, and tokens to the current span.

### TraceHandle.event(_:)
Records a named event on the current span.

```swift
@discardableResult
public func event(_ name: String) -> Self
```

### TraceHandle.tag(_:_:)
Attaches a span attribute using the string representation of `value`.

```swift
@discardableResult
public func tag<T: CustomStringConvertible & Sendable>(
    _ key: StaticString,
    _ value: T
) -> Self
```

### TraceHandle.tokens(input:output:)
Records the number of input and output tokens consumed by the operation.

```swift
@discardableResult
public func tokens(input: Int? = nil, output: Int? = nil) -> Self
```

### TraceHandle.responseModel(_:)
Records the model that generated the response.

```swift
@discardableResult
public func responseModel(_ value: ModelID) -> Self
```

### TraceHandle.chunk(_:)
Records a streaming chunk of tokens.

```swift
@discardableResult
public func chunk(_ tokens: Int = 1) -> Self
```

### TraceHandle.outputTokens(_:)
Records the total number of output tokens after streaming is complete.

```swift
@discardableResult
public func outputTokens(_ total: Int) -> Self
```

### TraceHandle.firstToken()
Marks the point at which the first output token was received during streaming.

```swift
@discardableResult
public func firstToken() -> Self
```

### TraceHandle.recordError(_:)
Records an error on the current span.

```swift
public func recordError(_ error: any Error)
```

---

## Capture Policy

### Terra.CapturePolicy
Controls whether raw content (prompts, responses) is captured in traces.

```swift
public enum CapturePolicy: Sendable, Hashable {
    /// The default capture policy — content is handled according to the active privacy policy.
    case `default`

    /// Captures raw content (prompts, responses) in traces regardless of privacy policy.
    case includeContent
}
```

---

## Lifecycle

### Terra.start(_:) async throws
Start Terra telemetry with a configuration value.

```swift
public static func start(_ config: Configuration = .init()) async throws
```

### Terra.shutdown() async
Shuts down Terra gracefully. Safe to call from any context. Idempotent.

```swift
public static func shutdown() async
```

### Terra.reconfigure(_:) async throws
Restarts Terra with a new configuration.

```swift
public static func reconfigure(_ config: Configuration) async throws
```

### Terra.reset() async
Shuts down Terra and clears any cached lifecycle configuration.

```swift
public static func reset() async
```

### Terra.lifecycleState
The current lifecycle state of the Terra runtime.

```swift
public static var lifecycleState: Terra.LifecycleState
```

### Terra.isRunning
`true` when Terra has been started and is actively collecting telemetry.

```swift
public static var isRunning: Bool
```

---

## Lifecycle State

### Terra.LifecycleState
The lifecycle state of the Terra runtime.

```swift
public enum LifecycleState: Sendable, Equatable {
    /// Terra has not been started, or has been shut down.
    case stopped

    /// Terra is starting. A start/reconfigure call is in progress.
    case starting

    /// Terra is running. Telemetry is being collected and exported.
    case running

    /// Terra is shutting down. A shutdown/reset/reconfigure call is in progress.
    case shuttingDown
}
```

---

## Configuration

### Terra.Configuration
Configuration for Terra initialization.

```swift
public struct Configuration: Sendable, Equatable {
    public var privacy: Terra.PrivacyPolicy
    public var destination: Destination
    public var features: Features
    public var persistence: Persistence
    public var profiling: Profiling

    public init(preset: Preset = .quickstart)
}
```

### Terra.Configuration.Preset
Predefined configuration presets for common use cases.

```swift
public enum Preset: Sendable, Equatable {
    /// Minimal setup for local development.
    case quickstart

    /// Production configuration with local persistence.
    case production

    /// Diagnostics configuration with profiling enabled.
    case diagnostics
}
```

### Terra.Configuration.Destination
Where telemetry data is sent.

```swift
public enum Destination: Sendable, Equatable {
    /// Sends telemetry to the local development dashboard (default).
    case localDashboard

    /// Sends telemetry to a custom OTLP-compatible endpoint.
    case endpoint(URL)
}
```

### Terra.Configuration.Persistence
Persistence settings for offline telemetry storage.

```swift
public enum Persistence: Sendable, Equatable {
    /// Disables persistence — telemetry is only exported when a backend is reachable.
    case off

    /// Balances write performance and export frequency for general use.
    case balanced(URL)

    /// Maximizes data durability at the cost of write throughput.
    case instant(URL)
}
```

### Terra.Configuration.Profiling
Hardware profiling options to collect system-level metrics alongside telemetry.

```swift
public struct Profiling: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int)

    public static let memory   = Profiling(rawValue: 1 << 0)
    public static let metal    = Profiling(rawValue: 1 << 1)
    public static let thermal  = Profiling(rawValue: 1 << 2)
    public static let power    = Profiling(rawValue: 1 << 3)
    public static let espresso = Profiling(rawValue: 1 << 4)
    public static let ane      = Profiling(rawValue: 1 << 5)

    public static let standard: Profiling = [.memory, .thermal]
    public static let extended: Profiling = [.memory, .thermal, .metal, .power]
    public static let all: Profiling      = [.memory, .thermal, .metal, .power, .espresso, .ane]
}
```

### Terra.Configuration.Features
Feature flags enabling specific Terra instrumentation modules.

```swift
public struct Features: OptionSet, Sendable, Equatable {
    public let rawValue: Int
    public init(rawValue: Int)

    /// Auto-instrument CoreML `MLModel.prediction(from:)` calls.
    public static let coreML    = Features(rawValue: 1 << 0)

    /// Auto-instrument HTTP requests to known AI API endpoints.
    public static let http      = Features(rawValue: 1 << 1)

    /// Enable session-level correlation IDs for grouping traces by user session.
    public static let sessions  = Features(rawValue: 1 << 2)

    /// Record OS Signpost intervals for fine-grained performance profiling in Instruments.
    public static let signposts = Features(rawValue: 1 << 3)

    /// Export structured diagnostic logs via OpenClaw.
    public static let logs      = Features(rawValue: 1 << 4)
}
```

---

## Privacy

### Terra.PrivacyPolicy
The privacy policy controlling how content (prompts, responses) is handled in traces.

```swift
public enum PrivacyPolicy: String, Sendable, Hashable {
    case redacted
    case lengthOnly
    case capturing
    case silent

    public var shouldCapture: Bool
    public func shouldCapture(includeContent: Bool) -> Bool
}
```

---

## Error Handling

### Terra.TerraError
Error type thrown by Terra operations.

```swift
public struct TerraError: Error, Sendable, Equatable, Hashable, LocalizedError {
    public let code: Code
    public let message: String
    public let context: [String: String]
    public let underlying: Underlying?

    public init(
        code: Code,
        message: String,
        context: [String: String] = [:],
        underlying: (any Error)? = nil
    )

    public var errorDescription: String? { message }
    public var remediationHint: String
}
```

### Terra.TerraError.Code
Structured error codes for Terra-specific error conditions.

```swift
public struct Code: Sendable, Hashable {
    public let rawValue: String
    public init(_ rawValue: String)

    public static let invalid_endpoint = Self("invalid_endpoint")
    public static let persistence_setup_failed = Self("persistence_setup_failed")
    public static let already_started = Self("already_started")
    public static let invalid_lifecycle_state = Self("invalid_lifecycle_state")
    public static let start_failed = Self("start_failed")
    public static let reconfigure_failed = Self("reconfigure_failed")
}
```

### Terra.TerraError.Underlying
Wraps an underlying error from the system or a dependency.

```swift
public struct Underlying: Sendable, Equatable, Hashable {
    public let type: String
    public let message: String

    public init(type: String, message: String)
    public init(error: any Error)
}
```

---

> **Note:** The following types are documented here for reference but are **NOT public APIs**:
> - `Terra.AgentContext`, `Terra.Scope<Kind>`, `Terra.TraceKeys`, `Terra.MetricNames`, `Terra.SpanNames`, `Terra.OperationName`
> - These are `internal` or `package` scoped and should not be used directly by consumers.

---

## Package-Scoped APIs (Internal)

The following APIs are package-scoped and intended for internal use within the Terra package or by companion packages:

### Terra.TelemetryContext
Context for telemetry operations.

```swift
package struct TelemetryContext: Sendable, Hashable {
    package enum Operation: String, Sendable, Hashable {
        case inference
        case streaming
        case embedding
        case agent
        case tool
        case safety
    }

    package let operation: Operation
    package let model: ModelID?
    package let name: String?
    package let provider: ProviderID?
    package let runtime: RuntimeID?
    package let capturePolicy: CapturePolicy

    package init(
        operation: Operation,
        model: ModelID? = nil,
        name: String? = nil,
        provider: ProviderID? = nil,
        runtime: RuntimeID? = nil,
        capturePolicy: CapturePolicy = .default
    )
}
```

### Terra.TraceHandle (Package Init)

```swift
package init(
    onEvent: @escaping @Sendable (String) -> Void,
    onAttribute: @escaping @Sendable (String, TraceScalar) -> Void,
    onError: @escaping @Sendable (any Error) -> Void,
    onTokens: @escaping @Sendable (Int?, Int?) -> Void = { _, _ in },
    onResponseModel: @escaping @Sendable (ModelID) -> Void = { _ in },
    onChunk: @escaping @Sendable (Int) -> Void = { _ in },
    onOutputTokens: @escaping @Sendable (Int) -> Void = { _ in },
    onFirstToken: @escaping @Sendable () -> Void = {}
)
```

### Terra.ScalarValue Protocol

```swift
package protocol ScalarValue: Sendable {
    var traceScalar: TraceScalar { get }
}
```

### Terra.TraceScalar

```swift
package enum TraceScalar: Sendable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
}
```

### Terra.TelemetryValue Protocol

```swift
package protocol TelemetryValue: Sendable {
    var telemetryAttributeValue: TelemetryAttributeValue { get }
}
```

### Terra.AttributeKey<Value>

```swift
package struct AttributeKey<Value: TelemetryValue>: Sendable, Hashable {
    package let name: String
    package init(_ name: String)
}
```

### Terra.AttributeBag

```swift
package struct AttributeBag: Sendable, Hashable {
    package var values: [String: TelemetryAttributeValue]
    package init()
    package mutating func set<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value)
    var openTelemetryAttributes: [String: AttributeValue]
}
```

### Terra.TelemetryAttributeValue

```swift
package enum TelemetryAttributeValue: Sendable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
}
```

### Terra.event(_:) / Terra.attr(_:_:)

```swift
package static func event(_ name: String) -> Metadata
package static func attr<Value: ScalarValue>(_ key: TraceKey<Value>, _ value: Value) -> Metadata
```

### Terra.inference / Terra.stream / etc. (Package-level call factories)

```swift
package static func inference(model: String, prompt: String? = nil) -> InferenceCall
package static func inference(_ request: InferenceRequest) -> InferenceCall
package static func stream(model: String, prompt: String? = nil) -> StreamingCall
package static func stream(_ request: StreamingRequest) -> StreamingCall
package static func embedding(model: String, inputCount: Int? = nil) -> EmbeddingCall
package static func embedding(_ request: EmbeddingRequest) -> EmbeddingCall
package static func agent(name: String, id: String? = nil) -> AgentCall
package static func agent(_ request: AgentRequest) -> AgentCall
package static func tool(name: String, callID: String, type: String? = nil) -> ToolCall
package static func tool(_ request: ToolRequest) -> ToolCall
package static func safetyCheck(name: String, subject: String? = nil) -> SafetyCheckCall
package static func safetyCheck(_ request: SafetyCheckRequest) -> SafetyCheckCall
```

### Request Types

```swift
package struct InferenceRequest: Sendable, Hashable {
    package var model: String
    package var prompt: String?
    package var includeContent: Bool
    package var maxOutputTokens: Int?
    package var temperature: Double?

    package init(model: String, prompt: String? = nil, includeContent: Bool = false,
                 maxOutputTokens: Int? = nil, temperature: Double? = nil)
    package static func chat(model: String, prompt: String? = nil) -> Self
    package func maxOutputTokens(_ value: Int) -> Self
    package func temperature(_ value: Double) -> Self
}

package struct StreamingRequest: Sendable, Hashable {
    package var model: String
    package var prompt: String?
    package var includeContent: Bool
    package var maxOutputTokens: Int?
    package var temperature: Double?
    package var expectedOutputTokens: Int?

    package init(model: String, prompt: String? = nil, includeContent: Bool = false,
                 maxOutputTokens: Int? = nil, temperature: Double? = nil,
                 expectedOutputTokens: Int? = nil)
    package static func chat(model: String, prompt: String? = nil) -> Self
    package func maxOutputTokens(_ value: Int) -> Self
    package func temperature(_ value: Double) -> Self
    package func expectedOutputTokens(_ value: Int) -> Self
}

package struct EmbeddingRequest: Sendable, Hashable {
    package var model: String
    package var inputCount: Int?
    package init(model: String, inputCount: Int? = nil)
}

package struct AgentRequest: Sendable, Hashable {
    package var name: String
    package var id: String?
    package init(name: String, id: String? = nil)
}

package struct ToolRequest: Sendable, Hashable {
    package var name: String
    package var callID: String
    package var type: String?
    package init(name: String, callID: String, type: String? = nil)
}

package struct SafetyCheckRequest: Sendable, Hashable {
    package var name: String
    package var subject: String?
    package var includeContent: Bool
    package init(name: String, subject: String? = nil, includeContent: Bool = false)
}
```

### Call Types (InferenceCall, StreamingCall, etc.)

All call types share a common interface:

```swift
package struct InferenceCall: Sendable {
    package func includeContent() -> Self
    package func runtime(_ value: String) -> Self
    package func provider(_ value: String) -> Self
    package func responseModel(_ value: String) -> Self
    package func tokens(input: Int? = nil, output: Int? = nil) -> Self
    package func temperature(_ value: Double) -> Self
    package func maxOutputTokens(_ value: Int) -> Self
    package func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self
    package func attributes(_ block: (inout AttributeBag) -> Void) -> Self
    @discardableResult
    package func execute<R>(_ body: @escaping @Sendable () async throws -> R) async rethrows -> R
    @discardableResult
    package func execute<R>(_ body: @escaping @Sendable (InferenceTrace) async throws -> R) async rethrows -> R
}

package struct StreamingCall: Sendable {
    package func includeContent() -> Self
    package func runtime(_ value: String) -> Self
    package func provider(_ value: String) -> Self
    package func temperature(_ value: Double) -> Self
    package func maxOutputTokens(_ value: Int) -> Self
    package func expectedOutputTokens(_ value: Int) -> Self
    package func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self
    package func attributes(_ block: (inout AttributeBag) -> Void) -> Self
    @discardableResult
    package func execute<R>(_ body: @escaping @Sendable () async throws -> R) async rethrows -> R
    @discardableResult
    package func execute<R>(_ body: @escaping @Sendable (StreamingTrace) async throws -> R) async rethrows -> R
}

package struct EmbeddingCall: Sendable { /* similar interface */ }
package struct AgentCall: Sendable { /* similar interface */ }
package struct ToolCall: Sendable { /* similar interface */ }
package struct SafetyCheckCall: Sendable { /* similar interface */ }
```

### Terra.Session Actor

```swift
package actor Session: Sendable {
    package init()
    package nonisolated func inference(model: String, prompt: String? = nil) -> InferenceCall
    package nonisolated func inference(_ request: InferenceRequest) -> InferenceCall
    package nonisolated func stream(model: String, prompt: String? = nil) -> StreamingCall
    package nonisolated func stream(_ request: StreamingRequest) -> StreamingCall
    package nonisolated func embedding(model: String, inputCount: Int? = nil) -> EmbeddingCall
    package nonisolated func embedding(_ request: EmbeddingRequest) -> EmbeddingCall
    package nonisolated func agent(name: String, id: String? = nil) -> AgentCall
    package nonisolated func agent(_ request: AgentRequest) -> AgentCall
    package nonisolated func tool(name: String, callID: String, type: String? = nil) -> ToolCall
    package nonisolated func tool(_ request: ToolRequest) -> ToolCall
    package nonisolated func safetyCheck(name: String, subject: String? = nil) -> SafetyCheckCall
    package nonisolated func safetyCheck(_ request: SafetyCheckRequest) -> SafetyCheckCall

    package func runInference<R>(
        request: InferenceRequest,
        attributes: AttributeBag,
        _ body: @Sendable (InferenceTrace) async throws -> R
    ) async rethrows -> R
    package func runStreaming<R>(
        request: StreamingRequest,
        attributes: AttributeBag,
        _ body: @Sendable (StreamingTrace) async throws -> R
    ) async rethrows -> R
    package func runEmbedding<R>(
        request: EmbeddingRequest,
        attributes: AttributeBag,
        _ body: @Sendable (EmbeddingTrace) async throws -> R
    ) async rethrows -> R
    package func runAgent<R>(
        request: AgentRequest,
        attributes: AttributeBag,
        _ body: @Sendable (AgentTrace) async throws -> R
    ) async rethrows -> R
    package func runTool<R>(
        request: ToolRequest,
        attributes: AttributeBag,
        _ body: @Sendable (ToolTrace) async throws -> R
    ) async rethrows -> R
    package func runSafetyCheck<R>(
        request: SafetyCheckRequest,
        attributes: AttributeBag,
        _ body: @Sendable (SafetyCheckTrace) async throws -> R
    ) async rethrows -> R
}
```

### TerraTrace Protocol

```swift
package protocol Trace: Sendable {
    @discardableResult func event(_ name: String) -> Self
    @discardableResult func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self
    @discardableResult func emit<E: TerraEvent>(_ event: E) -> Self
    func recordError(_ error: any Error)
}
```

### Trace Types

```swift
package struct InferenceTrace: Trace, Sendable {
    @discardableResult package func tokens(input: Int? = nil, output: Int? = nil) -> Self
    @discardableResult package func responseModel(_ value: String) -> Self
}

package struct StreamingTrace: Trace, Sendable {
    @discardableResult package func chunk(tokens: Int = 1) -> Self
    @discardableResult package func outputTokens(_ total: Int) -> Self
    @discardableResult package func firstToken() -> Self
}

package struct EmbeddingTrace: Trace, Sendable { /* standard Trace methods */ }
package struct AgentTrace: Trace, Sendable { /* standard Trace methods */ }
package struct ToolTrace: Trace, Sendable { /* standard Trace methods */ }
package struct SafetyCheckTrace: Trace, Sendable { /* standard Trace methods */ }
```

### TerraTraceable Protocol

```swift
package protocol TerraTraceable {
    var terraTokenUsage: TokenUsage? { get }
    var terraResponseModel: String? { get }
}

package struct TokenUsage: Sendable {
    package var input: Int?
    package var output: Int?
    package init(input: Int? = nil, output: Int? = nil)
}
```

### TerraEvent Protocol

```swift
package protocol TerraEvent: Sendable {
    static var name: StaticString { get }
    func encode(into attributes: inout AttributeBag)
}
```

### Privacy (Internal)

```swift
package enum ContentPolicy: Sendable, Hashable {
    case never
    case optIn
    case always
}

package enum RedactionStrategy: Sendable, Hashable {
    case drop
    case lengthOnly
    case hashHMACSHA256
    case hashSHA256
}

package struct Privacy: Sendable, Hashable {
    package var contentPolicy: ContentPolicy
    package var redaction: RedactionStrategy
    package var anonymizationKey: Data?
    package var emitLegacySHA256Attributes: Bool

    package init(
        contentPolicy: ContentPolicy = .never,
        redaction: RedactionStrategy = .hashHMACSHA256,
        anonymizationKey: Data? = nil,
        emitLegacySHA256Attributes: Bool = false
    )

    package static let `default` = Privacy()
    func shouldCapture(includeContent: Bool) -> Bool
}
```

### Configuration.Internal

```swift
package struct Installation {
    package var privacy: Privacy
    package var meterProvider: (any MeterProvider)?
    package var tracerProvider: (any TracerProvider)?
    package var loggerProvider: (any LoggerProvider)?
    package var registerProvidersAsGlobal: Bool

    package init(
        privacy: Privacy = .default,
        meterProvider: (any MeterProvider)? = nil,
        tracerProvider: (any TracerProvider)? = nil,
        loggerProvider: (any LoggerProvider)? = nil,
        registerProvidersAsGlobal: Bool = true
    )
}

package struct _ProfilingSettings: Sendable, Equatable {
    package var enableMemoryProfiler: Bool
    package var enableMetalProfiler: Bool
    package var enableThermalMonitor: Bool
    package var enablePowerProfiler: Bool
    package var enableEspressoCapture: Bool
    package var enableANEProfiler: Bool
}

package struct _Instrumentations: OptionSet, Sendable, Equatable {
    package static let coreML = _Instrumentations(rawValue: 1 << 0)
    package static let httpAIAPIs = _Instrumentations(rawValue: 1 << 1)
    package static let proxy = _Instrumentations(rawValue: 1 << 2)
    package static let openClawGateway = _Instrumentations(rawValue: 1 << 3)
    package static let openClawDiagnostics = _Instrumentations(rawValue: 1 << 4)
    package static let all: _Instrumentations
    package static let none = _Instrumentations([])
}

package struct _PersistenceSettings: Equatable, Sendable {
    package struct Performance: Equatable, Sendable {
        package static let balanced: Performance
        package static let instantDelivery: Performance
    }

    package var storageURL: URL
    package var performance: Performance
}
```

### OpenTelemetry Configuration

```swift
package enum TracerProviderStrategy: Equatable {
    case registerNew
    case augmentExisting
}

package struct OpenTelemetryConfiguration: Equatable {
    package var tracerProviderStrategy: TracerProviderStrategy
    package var enableTraces: Bool
    package var enableMetrics: Bool
    package var enableLogs: Bool
    package var enableSignposts: Bool
    package var enableSessions: Bool
    package var otlpTracesEndpoint: URL
    package var otlpMetricsEndpoint: URL
    package var otlpLogsEndpoint: URL
    package var metricsExportInterval: TimeInterval
    package var persistence: PersistenceConfiguration?
    package var serviceName: String?
    package var serviceVersion: String?
    package var resourceAttributes: [String: AttributeValue]
    package var traceSamplingRatio: Double?
}

package struct PersistenceConfiguration: Equatable {
    package var storageURL: URL
    package var performancePreset: PersistencePerformancePreset
    package var tracesStorageURL: URL { get }
    package var metricsStorageURL: URL { get }
    package var logsStorageURL: URL { get }
}
```

### Internal Span/Log Exporters

```swift
package final class SimulatorAwareSpanExporter: SpanExporter { /* ... */ }
package final class SimulatorAwareMetricExporter: MetricExporter { /* ... */ }
package final class SimulatorAwareLogExporter: LogRecordExporter { /* ... */ }
```

### Testing APIs

```swift
#if DEBUG
extension Terra {
    package static func lockTestingIsolation()
    package static func unlockTestingIsolation()
    internal static func resetOpenTelemetryForTesting()
}
#endif
```
