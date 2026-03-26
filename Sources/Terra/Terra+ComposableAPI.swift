import Foundation

extension Terra {
  /// Controls whether content-derived telemetry may be emitted for a specific call.
  ///
  /// By default, Terra excludes prompt and response content from traces to
  /// protect sensitive data and reduce storage costs. Set `.includeContent` to
  /// opt a specific call into content capture, while the active privacy policy
  /// still determines whether Terra stores length-only, hashed, or no content
  /// signal at all.
  ///
  /// - Note: Content capture is also controlled by `Terra.PrivacyPolicy`. Even with
  ///   `.includeContent`, privacy settings may redact or anonymize content before it
  ///   reaches the trace exporter.
  public enum CapturePolicy: Sendable, Hashable {
    /// The default capture policy — content is handled according to the active privacy policy.
    case `default`

    /// Opts a single call into content capture.
    ///
    /// Use this when you want Terra to emit content-derived telemetry for a
    /// specific operation. The active privacy policy still governs whether the
    /// resulting span stores length-only, hashed, or no content signal.
    case includeContent
  }

  package protocol ScalarValue: Sendable {
    var traceScalar: TraceScalar { get }
  }

  package enum TraceScalar: Sendable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
  }

  package struct TraceKey<Value: ScalarValue>: Sendable, Hashable {
    package let name: String

    package init(_ name: String) {
      self.name = name
    }
  }

  package struct TraceAttribute: Sendable, Hashable {
    package let name: String
    package let value: TraceScalar

    package init(name: String, value: TraceScalar) {
      self.name = name
      self.value = value
    }
  }

  package enum Metadata: Sendable, Hashable {
    case event(String)
    case attribute(TraceAttribute)
  }

  @resultBuilder
  package enum MetadataBuilder {
    package static func buildBlock(_ components: [Metadata]...) -> [Metadata] {
      components.flatMap { $0 }
    }

    package static func buildExpression(_ expression: Metadata) -> [Metadata] {
      [expression]
    }

    package static func buildExpression(_ expression: [Metadata]) -> [Metadata] {
      expression
    }

    package static func buildOptional(_ component: [Metadata]?) -> [Metadata] {
      component ?? []
    }

    package static func buildEither(first component: [Metadata]) -> [Metadata] {
      component
    }

    package static func buildEither(second component: [Metadata]) -> [Metadata] {
      component
    }

    package static func buildArray(_ components: [[Metadata]]) -> [Metadata] {
      components.flatMap { $0 }
    }

    package static func buildLimitedAvailability(_ component: [Metadata]) -> [Metadata] {
      component
    }
  }

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
    package let model: String?
    package let name: String?
    package let provider: ProviderID?
    package let runtime: RuntimeID?
    package let capturePolicy: CapturePolicy

    package init(
      operation: Operation,
      model: String? = nil,
      name: String? = nil,
      provider: ProviderID? = nil,
      runtime: RuntimeID? = nil,
      capturePolicy: CapturePolicy = .default
    ) {
      self.operation = operation
      self.model = model
      self.name = name
      self.provider = provider
      self.runtime = runtime
      self.capturePolicy = capturePolicy
    }
  }

  package protocol TelemetryEngine: Sendable {
    func run<R: Sendable>(
      context: TelemetryContext,
      attributes: [TraceAttribute],
      _ body: @escaping @Sendable (TraceHandle) async throws -> R
    ) async throws -> R
  }

  /// Creates a metadata entry representing a named event, for use in the `@Terra.MetadataBuilder` result builder.
  ///
  /// Use this within the `metadata:` closure of a composable operation to attach
  /// arbitrary named events to the span before the operation body runs.
  ///
  /// ```swift
  /// Terra.infer("gpt-4o-mini", ...)
  ///     .run { handle in
  ///         // ...
  ///     }
  /// ```
  ///
  /// - Parameter name: A meaningful name for the event (e.g., `"preprocessing-complete"`).
  /// - Returns: A `Metadata` event entry for use in `@Terra.MetadataBuilder`.
  package static func event(_ name: String) -> Metadata {
    .event(name)
  }

  /// Creates a metadata entry representing a typed attribute, for use in the `@Terra.MetadataBuilder` result builder.
  ///
  /// Use this within the `metadata:` closure to attach attributes to the span
  /// before the operation body runs. The attribute name is derived from the `TraceKey`.
  ///
  /// - Parameters:
  ///   - key: The `TraceKey` that names the attribute (e.g., `Terra.TraceKeys.temperature`).
  ///   - value: The value for the attribute. Must conform to `ScalarValue` (String, Int, Double, Bool).
  /// - Returns: A `Metadata` attribute entry for use in `@Terra.MetadataBuilder`.
  package static func attr<Value: ScalarValue>(_ key: TraceKey<Value>, _ value: Value) -> Metadata {
    .attribute(.init(name: key.name, value: value.traceScalar))
  }

  package enum TraceKeys {
    static let runtime = TraceKey<RuntimeID>("terra.runtime")
    static let provider = TraceKey<ProviderID>("gen_ai.provider.name")
    static let responseModel = TraceKey<String>("gen_ai.response.model")
    static let inputTokens = TraceKey<Int>("gen_ai.usage.input_tokens")
    static let outputTokens = TraceKey<Int>("gen_ai.usage.output_tokens")
    static let temperature = TraceKey<Double>("gen_ai.request.temperature")
    static let maxOutputTokens = TraceKey<Int>("gen_ai.request.max_tokens")
  }

  /// A handle for adding events, attributes, and tokens to the current span.
  ///
  /// `TraceHandle` is passed into the body of a composable operation (e.g., `Terra.infer(...)`)
  /// and provides methods to add rich context to the active trace span. All methods return
  /// `self` for fluent chaining.
  ///
  /// ```swift
  /// try await Terra.infer("gpt-4o-mini", prompt: "Hello") { handle in
  ///     handle.event("prompt-processed")
  ///         .tokens(input: 5, output: nil)
  ///         .responseModel("gpt-4o-mini")
  ///     return response
  /// }
  /// ```
  public struct TraceHandle: Sendable {
    private let onEvent: @Sendable (String) -> Void
    private let onAttribute: @Sendable (String, TraceScalar) -> Void
    private let onError: @Sendable (any Error) -> Void
    private let onTokens: @Sendable (Int?, Int?) -> Void
    private let onResponseModel: @Sendable (String) -> Void
    private let onChunk: @Sendable (Int) -> Void
    private let onOutputTokens: @Sendable (Int) -> Void
    private let onFirstToken: @Sendable () -> Void

    package init(
      onEvent: @escaping @Sendable (String) -> Void,
      onAttribute: @escaping @Sendable (String, TraceScalar) -> Void,
      onError: @escaping @Sendable (any Error) -> Void,
      onTokens: @escaping @Sendable (Int?, Int?) -> Void = { _, _ in },
      onResponseModel: @escaping @Sendable (String) -> Void = { _ in },
      onChunk: @escaping @Sendable (Int) -> Void = { _ in },
      onOutputTokens: @escaping @Sendable (Int) -> Void = { _ in },
      onFirstToken: @escaping @Sendable () -> Void = {}
    ) {
      self.onEvent = onEvent
      self.onAttribute = onAttribute
      self.onError = onError
      self.onTokens = onTokens
      self.onResponseModel = onResponseModel
      self.onChunk = onChunk
      self.onOutputTokens = onOutputTokens
      self.onFirstToken = onFirstToken
    }

    /// Records a named event on the current span.
    ///
    /// Events are zero-attribute timestamped markers useful for marking significant
    /// moments in the operation (e.g., "first-token", "streaming-started").
    ///
    /// - Parameters:
    ///   - name: A meaningful name for the event (e.g., "tool-call-start", "content-filter-triggered").
    /// - Returns: `self` for chaining.
    @discardableResult
    public func event(_ name: String) -> Self {
      onEvent(name)
      return self
    }

    /// Attaches a span attribute using the string representation of `value`.
    ///
    /// All values are stored as OpenTelemetry string attributes regardless of their
    /// Swift type, so numeric aggregation (sum, avg, percentile) on backend dashboards
    /// will not work on values added via `tag`. Use `.tokens(input:output:)` and
    /// `.responseModel(_:)` for structured numeric and identifier attributes.
    @discardableResult
    public func tag<T: CustomStringConvertible & Sendable>(_ key: StaticString, _ value: T) -> Self {
      onAttribute(key.description, .string(value.description))
      return self
    }

    /// Records the number of input and output tokens consumed by the operation.
    ///
    /// Token counts are recorded as OpenTelemetry metrics (`gen_ai.usage.input_tokens`
    /// and `gen_ai.usage.output_tokens`) on the span, enabling usage analytics and
    /// cost tracking per model or provider.
    ///
    /// - Parameters:
    ///   - input: Number of tokens in the prompt/request. Pass `nil` if unknown.
    ///   - output: Number of tokens in the response. Pass `nil` if streaming is not yet complete.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func tokens(input: Int? = nil, output: Int? = nil) -> Self {
      onTokens(input, output)
      return self
    }

    /// Records the model that generated the response.
    ///
    /// Use this when the model used for the response may differ from the requested model
    /// (e.g., when a provider routes to a different model). The value is recorded as the
    /// `gen_ai.response.model` span attribute.
    ///
    /// - Parameter value: The model ID that generated the response.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func responseModel(_ value: String) -> Self {
      onResponseModel(value)
      return self
    }

    /// Records the model that generated the response using a compatibility wrapper.
    @available(*, deprecated, message: "Use String model names directly.")
    @discardableResult
    public func responseModel(_ value: ModelID) -> Self {
      responseModel(value.rawValue)
    }

    /// Records a streaming chunk of tokens.
    ///
    /// Each call represents a batch of tokens received during streaming. The cumulative
    /// total across all `chunk` calls is used to compute total output tokens unless
    /// `outputTokens(_:)` is called separately.
    ///
    /// - Parameter tokens: Number of tokens in this chunk. Defaults to `1`.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func chunk(_ tokens: Int = 1) -> Self {
      onChunk(tokens)
      return self
    }

    /// Records the total number of output tokens after streaming is complete.
    ///
    /// Call this once at the end of a streaming operation instead of calling `chunk`
    /// repeatedly. If both are called, `outputTokens` takes precedence for the final count.
    ///
    /// - Parameter total: Total output tokens for the entire response.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func outputTokens(_ total: Int) -> Self {
      onOutputTokens(total)
      return self
    }

    /// Marks the point at which the first output token was received during streaming.
    ///
    /// This is useful for measuring "time to first token" (TTFT), a key latency
    /// metric for streaming responses. The timestamp is recorded as a span event.
    ///
    /// - Returns: `self` for chaining.
    @discardableResult
    public func firstToken() -> Self {
      onFirstToken()
      return self
    }

    /// Records an error on the current span.
    ///
    /// The error is recorded with its `localizedDescription` as the event name and
    /// the full error attached as the span's error state. This ensures the span is
    /// marked as failed in tracing backends.
    ///
    /// - Parameter error: The error to record on the span.
    public func recordError(_ error: any Error) {
      onError(error)
    }
  }

  /// Represents a composable telemetry operation that wraps an AI call.
  ///
  /// `Operation` is the core type for instrumenting inference, streaming, embedding,
  /// agent, tool, and safety-check calls. It provides a fluent, trace-aware interface
  /// for making AI calls with automatic span creation, attribute recording, and
  /// error propagation to the active trace.
  ///
  /// Use the factory methods (`Terra.infer(...)`, `Terra.stream(...)`, etc.) to create
  /// an `Operation`, then call `.run { handle in ... }` to execute it with a trace handle
  /// for adding custom events and attributes.
  ///
  /// ```swift
  /// let operation = Terra.infer("gpt-4o-mini", prompt: "What is 2+2?")
  ///     .capture(.includeContent)
  ///
  /// try await operation.run { handle in
  ///     let response = try await model.predict(handle: handle)
  ///     return response
  /// }
  /// ```
  public struct Operation: Sendable {
    private var operation: _Operation
    private var capturePolicy: CapturePolicy = .default
    private var attributes: [_TraceAttribute] = []
    private var metadataEntries: [Metadata] = []
    private var parentSpan: SpanHandle?

    fileprivate init(operation: _Operation) {
      self.operation = operation
    }

    /// Overrides the capture policy for this operation.
    ///
    /// By default, an operation inherits the capture policy it was created with.
    /// Use this method to override it on a per-operation basis, for example to
    /// temporarily capture content for a specific call while keeping others redacted.
    ///
    /// - Parameter policy: The capture policy to apply to this operation.
    /// - Returns: A new `Operation` with the specified capture policy.
    public func capture(_ policy: CapturePolicy) -> Self {
      var copy = self
      copy.capturePolicy = policy
      return copy
    }

    /// Binds the operation to an explicit Terra parent span.
    ///
    /// Use this when child work must stay attached to a long-lived manual or agentic
    /// span even if the call executes outside the parent closure's immediate task context.
    public func under(_ parent: SpanHandle) -> Self {
      var copy = self
      copy.parentSpan = parent
      return copy
    }

    /// Executes the operation with a trace handle.
    ///
    /// This overload passes a `TraceHandle` to the body, allowing you to record
    /// custom events, attributes, and metrics on the active span. The handle must
    /// be captured and used within the async body to ensure data is attached to
    /// the correct span.
    ///
    /// - Parameter body: An async closure that receives a `TraceHandle` and performs the work.
    /// - Returns: The result of the body, propagated unchanged.
    /// - Throws: Any error thrown by `body`, with error state recorded on the span.
    @discardableResult
    public func run<R: Sendable>(_ body: @escaping @Sendable () async throws -> R) async rethrows -> R {
      try await run { _ in
        try await body()
      }
    }

    /// Executes the operation, ignoring the trace handle.
    ///
    /// Use this overload when you only need automatic span creation and error recording,
    /// but do not need to add custom events or attributes.
    ///
    /// - Parameter body: An async closure that performs the work.
    /// - Returns: The result of the body.
    /// - Throws: Any error thrown by `body`, with error state recorded on the span.
    @discardableResult
    public func run<R: Sendable>(_ body: @escaping @Sendable (TraceHandle) async throws -> R) async rethrows -> R {
      let attributes = _mergedAttributes()
      let events = _metadataEvents()
      return try await _run(
        operation: operation,
        capturePolicy: capturePolicy,
        attributes: attributes,
        parent: parentSpan
      ) { handle in
        for event in events {
          _ = handle.event(event)
        }
        return try await body(handle)
      }
    }

    @discardableResult
    package func run<R: Sendable, Engine: TelemetryEngine>(
      using engine: Engine,
      _ body: @escaping @Sendable () async throws -> R
    ) async throws -> R {
      try await run(using: engine) { _ in
        try await body()
      }
    }

    @discardableResult
    package func run<R: Sendable, Engine: TelemetryEngine>(
      using engine: Engine,
      _ body: @escaping @Sendable (TraceHandle) async throws -> R
    ) async throws -> R {
      let context = _context(capturePolicy: capturePolicy)
      var seamAttributes = _mergedAttributes().map { TraceAttribute(name: $0.name, value: $0.value) }
      if let provider = context.provider {
        seamAttributes.append(.init(name: TraceKeys.provider.name, value: provider.traceScalar))
      }
      if let runtime = context.runtime {
        seamAttributes.append(.init(name: TraceKeys.runtime.name, value: runtime.traceScalar))
      }
      let events = _metadataEvents()
      return try await engine.run(
        context: context,
        attributes: seamAttributes,
        { handle in
          for event in events {
            _ = handle.event(event)
          }
          return try await body(handle)
        }
      )
    }

    private func _mergedAttributes() -> [_TraceAttribute] {
      var merged = attributes
      for item in metadataEntries {
        if case .attribute(let attribute) = item {
          merged.append(.init(name: attribute.name, value: attribute.value))
        }
      }
      return merged
    }

    private func _metadataEvents() -> [String] {
      metadataEntries.compactMap {
        guard case .event(let name) = $0 else { return nil }
        return name
      }
    }

    private func _context(capturePolicy: CapturePolicy) -> TelemetryContext {
      switch operation {
      case .infer(let operation):
        .init(
          operation: .inference,
          model: operation.model,
          provider: operation.provider,
          runtime: operation.runtime,
          capturePolicy: capturePolicy
        )
      case .stream(let operation):
        .init(
          operation: .streaming,
          model: operation.model,
          provider: operation.provider,
          runtime: operation.runtime,
          capturePolicy: capturePolicy
        )
      case .embed(let operation):
        .init(
          operation: .embedding,
          model: operation.model,
          provider: operation.provider,
          runtime: operation.runtime,
          capturePolicy: capturePolicy
        )
      case .agent(let operation):
        .init(
          operation: .agent,
          name: operation.name,
          provider: operation.provider,
          runtime: operation.runtime,
          capturePolicy: capturePolicy
        )
      case .tool(let operation):
        .init(
          operation: .tool,
          name: operation.name,
          provider: operation.provider,
          runtime: operation.runtime,
          capturePolicy: capturePolicy
        )
      case .safety(let operation):
        .init(
          operation: .safety,
          name: operation.name,
          provider: operation.provider,
          runtime: operation.runtime,
          capturePolicy: capturePolicy
        )
      }
    }
  }

  /// Creates an inference operation for a non-streaming model call.
  ///
  /// Use this factory method to create a traced, composable inference operation
  /// that wraps a standard (non-streaming) chat or completion call. The operation
  /// creates an OpenTelemetry span with model, provider, and runtime attributes,
  /// and supports recording token usage and custom events via the `TraceHandle`.
  ///
  /// - Parameters:
  ///   - model: The model identifier for the inference call (e.g., `"gpt-4o-mini"`).
  ///   - prompt: The input prompt. Content is subject to the active `CapturePolicy` and privacy settings.
  ///   - provider: The AI provider (e.g., `.openAI`). Inferred from the runtime if `nil`.
  ///   - runtime: The execution runtime (e.g., `.http_api`). Inferred from instrumentation if `nil`.
  ///   - temperature: Sampling temperature passed to the model. Recorded as a span attribute.
  ///   - maxTokens: Maximum output tokens. Recorded as a span attribute.
  /// - Returns: A new `Operation` ready for execution via `.run { handle in ... }`.
  public static func infer(
    _ model: String,
    prompt: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil,
    temperature: Double? = nil,
    maxTokens: Int? = nil
  ) -> Operation {
    Operation(operation: .infer(.init(
      model: model,
      prompt: prompt,
      provider: provider,
      runtime: runtime,
      temperature: temperature,
      maxTokens: maxTokens
    )))
  }

  public static func infer(
    _ model: String,
    messages: [ChatMessage],
    prompt: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil,
    temperature: Double? = nil,
    maxTokens: Int? = nil
  ) -> Operation {
    Operation(operation: .infer(.init(
      model: model,
      prompt: prompt,
      messages: messages,
      provider: provider,
      runtime: runtime,
      temperature: temperature,
      maxTokens: maxTokens
    )))
  }

  /// Creates a model-inference operation using a compatibility wrapper.
  @available(*, deprecated, message: "Use String model names directly.")
  public static func infer(
    _ model: ModelID,
    prompt: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil,
    temperature: Double? = nil,
    maxTokens: Int? = nil
  ) -> Operation {
    infer(model.rawValue, prompt: prompt, provider: provider, runtime: runtime, temperature: temperature, maxTokens: maxTokens)
  }

  /// Creates a streaming inference operation for a model call with token-by-token streaming.
  ///
  /// Use this factory method when making streaming calls where tokens are received
  /// incrementally. The resulting `Operation` creates a span that records chunk events,
  /// time-to-first-token, and total output token counts.
  ///
  /// - Parameters:
  ///   - model: The model identifier for the inference call.
  ///   - prompt: The input prompt. Content is subject to the active `CapturePolicy`.
  ///   - provider: The AI provider. Inferred from the runtime if `nil`.
  ///   - runtime: The execution runtime. Inferred from instrumentation if `nil`.
  ///   - temperature: Sampling temperature passed to the model.
  ///   - maxTokens: Maximum output tokens.
  ///   - expectedTokens: Expected total output tokens (used for progress tracking). Optional.
  /// - Returns: A new `Operation` for streaming execution.
  public static func stream(
    _ model: String,
    prompt: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil,
    temperature: Double? = nil,
    maxTokens: Int? = nil,
    expectedTokens: Int? = nil
  ) -> Operation {
    Operation(operation: .stream(.init(
      model: model,
      prompt: prompt,
      provider: provider,
      runtime: runtime,
      temperature: temperature,
      maxTokens: maxTokens,
      expectedTokens: expectedTokens
    )))
  }

  /// Creates a streaming inference operation using a compatibility wrapper.
  @available(*, deprecated, message: "Use String model names directly.")
  public static func stream(
    _ model: ModelID,
    prompt: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil,
    temperature: Double? = nil,
    maxTokens: Int? = nil,
    expectedTokens: Int? = nil
  ) -> Operation {
    stream(
      model.rawValue,
      prompt: prompt,
      provider: provider,
      runtime: runtime,
      temperature: temperature,
      maxTokens: maxTokens,
      expectedTokens: expectedTokens
    )
  }

  /// Creates an embedding operation for generating vector representations of text.
  ///
  /// Use this for embedding calls where text is converted to numerical vectors.
  /// The span records model, provider, runtime, and input token count.
  ///
  /// - Parameters:
  ///   - model: The model identifier for the embedding model.
  ///   - inputCount: Number of input text segments/items. Recorded as a span attribute.
  ///   - provider: The AI provider. Inferred from the runtime if `nil`.
  ///   - runtime: The execution runtime. Inferred from instrumentation if `nil`.
  /// - Returns: A new `Operation` for embedding execution.
  public static func embed(
    _ model: String,
    inputCount: Int? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil
  ) -> Operation {
    Operation(operation: .embed(.init(
      model: model,
      inputCount: inputCount,
      provider: provider,
      runtime: runtime
    )))
  }

  /// Creates an embedding operation using a compatibility wrapper.
  @available(*, deprecated, message: "Use String model names directly.")
  public static func embed(
    _ model: ModelID,
    inputCount: Int? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil
  ) -> Operation {
    embed(model.rawValue, inputCount: inputCount, provider: provider, runtime: runtime)
  }

  /// Creates an agent operation representing an autonomous agentic loop.
  ///
  /// Use this to trace a complete agentic turn — from the model's decision-making
  /// through any tool calls and safety checks it performs. The span covers the full
  /// agent loop and records the agent name, provider, and runtime.
  ///
  /// - Parameters:
  ///   - name: A human-readable name for the agent (e.g., `"code-reviewer"`, `"research-assistant"`).
  ///   - id: An optional stable identifier for this specific agent instance or session.
  ///   - provider: The AI provider powering the agent. Inferred from the runtime if `nil`.
  ///   - runtime: The execution runtime. Inferred from instrumentation if `nil`.
  /// - Returns: A new `Operation` for the agentic operation.
  public static func agent(
    _ name: String,
    id: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil
  ) -> Operation {
    Operation(operation: .agent(.init(name: name, id: id, provider: provider, runtime: runtime)))
  }

  /// Creates a tool-call operation representing a single tool invocation within an agentic workflow.
  ///
  /// `callId` defaults to a UUID, but can be provided explicitly when
  /// the calling context already has a meaningful identifier. The span records
  /// the tool name, call ID, tool type, provider, and runtime.
  ///
  /// - Parameters:
  ///   - name: The name of the tool being invoked (e.g., `"web-search"`, `"calculator"`).
  ///   - callId: A unique identifier for this tool call. Auto-generated as a UUID if omitted.
  ///   - type: An optional type descriptor for the tool (e.g., `"function"`, `"retrieval"`).
  ///   - provider: The AI provider. Inferred from the runtime if `nil`.
  ///   - runtime: The execution runtime. Inferred from instrumentation if `nil`.
  /// - Returns: A new `Operation` for the tool call.
  public static func tool(
    _ name: String,
    type: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil
  ) -> Operation {
    tool(name, callId: UUID().uuidString, type: type, provider: provider, runtime: runtime)
  }

  /// Creates a tool-call operation representing a single tool invocation with an explicit call ID.
  ///
  /// Use this overload when the calling context already has a stable identifier and
  /// you want the trace to correlate with upstream agent/tooling records.
  public static func tool(
    _ name: String,
    callId: String,
    type: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil
  ) -> Operation {
    Operation(operation: .tool(.init(name: name, callId: callId, type: type, provider: provider, runtime: runtime)))
  }

  /// Creates a tool-call operation using the legacy `callID:` label.
  @available(*, deprecated, message: "Use callId: instead of callID:.")
  public static func tool(
    _ name: String,
    callID: String,
    type: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil
  ) -> Operation {
    tool(name, callId: callID, type: type, provider: provider, runtime: runtime)
  }

  /// Creates a tool-call operation using a compatibility wrapper.
  @available(*, deprecated, message: "Use String tool call identifiers directly.")
  public static func tool(
    _ name: String,
    callId: ToolCallID,
    type: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil
  ) -> Operation {
    tool(name, callId: callId.rawValue, type: type, provider: provider, runtime: runtime)
  }

  /// Creates a tool-call operation using a compatibility wrapper and legacy label.
  @available(*, deprecated, message: "Use callId: with a String identifier.")
  public static func tool(
    _ name: String,
    callID: ToolCallID,
    type: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil
  ) -> Operation {
    tool(name, callId: callID.rawValue, type: type, provider: provider, runtime: runtime)
  }

  /// Creates a safety-evaluation operation representing a content safety check.
  ///
  /// Use this to trace safety evaluations performed on model inputs or outputs.
  /// The span records the name of the safety check, the subject being evaluated,
  /// the provider, and the runtime.
  ///
  /// - Parameters:
  ///   - name: The name of the safety check (e.g., `"harmful-content"`, `"pii-detection"`).
  ///   - subject: The text or content being evaluated. Optional.
  ///   - provider: The AI provider. Inferred from the runtime if `nil`.
  ///   - runtime: The execution runtime. Inferred from instrumentation if `nil`.
  /// - Returns: A new `Operation` for the safety check.
  public static func safety(
    _ name: String,
    subject: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil
  ) -> Operation {
    Operation(operation: .safety(.init(name: name, subject: subject, provider: provider, runtime: runtime)))
  }
}

extension String: Terra.ScalarValue {
  package var traceScalar: Terra.TraceScalar { .string(self) }
}

extension Int: Terra.ScalarValue {
  package var traceScalar: Terra.TraceScalar { .int(self) }
}

extension Double: Terra.ScalarValue {
  package var traceScalar: Terra.TraceScalar { .double(self) }
}

extension Bool: Terra.ScalarValue {
  package var traceScalar: Terra.TraceScalar { .bool(self) }
}

private extension Terra.TraceScalar {
  var telemetry: Terra.TelemetryAttributeValue {
    switch self {
    case .string(let value):
      return .string(value)
    case .int(let value):
      return .int(value)
    case .double(let value):
      return .double(value)
    case .bool(let value):
      return .bool(value)
    }
  }
}

private extension Terra {
  struct _TraceAttribute: Sendable, Hashable {
    let name: String
    let value: TraceScalar
  }

  struct _Infer: Sendable {
    var model: String
    var prompt: String?
    var messages: [ChatMessage]?
    var provider: ProviderID?
    var runtime: RuntimeID?
    var temperature: Double?
    var maxTokens: Int?
  }

  struct _Stream: Sendable {
    var model: String
    var prompt: String?
    var provider: ProviderID?
    var runtime: RuntimeID?
    var temperature: Double?
    var maxTokens: Int?
    var expectedTokens: Int?
  }

  struct _Embed: Sendable {
    var model: String
    var inputCount: Int?
    var provider: ProviderID?
    var runtime: RuntimeID?
  }

  struct _Agent: Sendable {
    var name: String
    var id: String?
    var provider: ProviderID?
    var runtime: RuntimeID?
  }

  struct _Tool: Sendable {
    var name: String
    var callId: String
    var type: String?
    var provider: ProviderID?
    var runtime: RuntimeID?
  }

  struct _Safety: Sendable {
    var name: String
    var subject: String?
    var provider: ProviderID?
    var runtime: RuntimeID?
  }

  enum _Operation: Sendable {
    case infer(_Infer)
    case stream(_Stream)
    case embed(_Embed)
    case agent(_Agent)
    case tool(_Tool)
    case safety(_Safety)
  }

  static func _merge(_ attributes: [_TraceAttribute], into bag: inout AttributeBag) {
    for attribute in attributes {
      bag.values[attribute.name] = attribute.value.telemetry
    }
  }

  static func _recordAttribute<T: Trace>(_ name: String, _ value: TraceScalar, on trace: T) {
    switch value {
    case .string(let scalar):
      _ = trace.attribute(.init(name), scalar)
    case .int(let scalar):
      _ = trace.attribute(.init(name), scalar)
    case .double(let scalar):
      _ = trace.attribute(.init(name), scalar)
    case .bool(let scalar):
      _ = trace.attribute(.init(name), scalar)
    }
  }

  static func _run<R: Sendable>(
    operation: _Operation,
    capturePolicy: CapturePolicy,
    attributes: [_TraceAttribute],
    parent: SpanHandle? = nil,
    _ body: @escaping @Sendable (TraceHandle) async throws -> R
  ) async rethrows -> R {
    switch operation {
    case .infer(let operation):
      let request = InferenceRequest(
        model: operation.model,
        prompt: operation.prompt,
        messages: operation.messages
      )
      var call = inference(request)
      if let parent { call = call.under(parent) }
      if capturePolicy == .includeContent { call = call.includeContent() }
      if let provider = operation.provider { call = call.provider(provider.rawValue) }
      if let runtime = operation.runtime { call = call.runtime(runtime.rawValue) }
      if let temperature = operation.temperature { call = call.temperature(temperature) }
      if let maxTokens = operation.maxTokens { call = call.maxOutputTokens(maxTokens) }
      if !attributes.isEmpty { call = call.attributes { _merge(attributes, into: &$0) } }
      return try await call.execute { trace in
        let handle = TraceHandle(
          onEvent: { _ = trace.event($0) },
          onAttribute: { _recordAttribute($0, $1, on: trace) },
          onError: { trace.recordError($0) },
          onTokens: { _ = trace.tokens(input: $0, output: $1) },
          onResponseModel: { _ = trace.responseModel($0) }
        )
        return try await body(handle)
      }

    case .stream(let operation):
      var call = stream(model: operation.model, prompt: operation.prompt)
      if let parent { call = call.under(parent) }
      if capturePolicy == .includeContent { call = call.includeContent() }
      if let provider = operation.provider { call = call.provider(provider.rawValue) }
      if let runtime = operation.runtime { call = call.runtime(runtime.rawValue) }
      if let temperature = operation.temperature { call = call.temperature(temperature) }
      if let maxTokens = operation.maxTokens { call = call.maxOutputTokens(maxTokens) }
      if let expectedTokens = operation.expectedTokens { call = call.expectedOutputTokens(expectedTokens) }
      if !attributes.isEmpty { call = call.attributes { _merge(attributes, into: &$0) } }
      return try await call.execute { trace in
        let handle = TraceHandle(
          onEvent: { _ = trace.event($0) },
          onAttribute: { _recordAttribute($0, $1, on: trace) },
          onError: { trace.recordError($0) },
          onChunk: { _ = trace.chunk(tokens: $0) },
          onOutputTokens: { _ = trace.outputTokens($0) },
          onFirstToken: { _ = trace.firstToken() }
        )
        return try await body(handle)
      }

    case .embed(let operation):
      var call = embedding(model: operation.model, inputCount: operation.inputCount)
      if let parent { call = call.under(parent) }
      if capturePolicy == .includeContent { call = call.includeContent() }
      if let provider = operation.provider { call = call.provider(provider.rawValue) }
      if let runtime = operation.runtime { call = call.runtime(runtime.rawValue) }
      if !attributes.isEmpty { call = call.attributes { _merge(attributes, into: &$0) } }
      return try await call.execute { trace in
        let handle = TraceHandle(
          onEvent: { _ = trace.event($0) },
          onAttribute: { _recordAttribute($0, $1, on: trace) },
          onError: { trace.recordError($0) }
        )
        return try await body(handle)
      }

    case .agent(let operation):
      var call = agent(name: operation.name, id: operation.id)
      if let parent { call = call.under(parent) }
      if capturePolicy == .includeContent { call = call.includeContent() }
      if let provider = operation.provider { call = call.provider(provider.rawValue) }
      if let runtime = operation.runtime { call = call.runtime(runtime.rawValue) }
      if !attributes.isEmpty { call = call.attributes { _merge(attributes, into: &$0) } }
      return try await call.execute { trace in
        let handle = TraceHandle(
          onEvent: { _ = trace.event($0) },
          onAttribute: { _recordAttribute($0, $1, on: trace) },
          onError: { trace.recordError($0) }
        )
        return try await body(handle)
      }

    case .tool(let operation):
      var call = tool(name: operation.name, callId: operation.callId, type: operation.type)
      if let parent { call = call.under(parent) }
      if capturePolicy == .includeContent { call = call.includeContent() }
      if let provider = operation.provider { call = call.provider(provider.rawValue) }
      if let runtime = operation.runtime { call = call.runtime(runtime.rawValue) }
      if !attributes.isEmpty { call = call.attributes { _merge(attributes, into: &$0) } }
      return try await call.execute { trace in
        let handle = TraceHandle(
          onEvent: { _ = trace.event($0) },
          onAttribute: { _recordAttribute($0, $1, on: trace) },
          onError: { trace.recordError($0) }
        )
        return try await body(handle)
      }

    case .safety(let operation):
      var call = safetyCheck(name: operation.name, subject: operation.subject)
      if let parent { call = call.under(parent) }
      if capturePolicy == .includeContent { call = call.includeContent() }
      if let provider = operation.provider { call = call.provider(provider.rawValue) }
      if let runtime = operation.runtime { call = call.runtime(runtime.rawValue) }
      if !attributes.isEmpty { call = call.attributes { _merge(attributes, into: &$0) } }
      return try await call.execute { trace in
        let handle = TraceHandle(
          onEvent: { _ = trace.event($0) },
          onAttribute: { _recordAttribute($0, $1, on: trace) },
          onError: { trace.recordError($0) }
        )
        return try await body(handle)
      }
    }
  }
}
