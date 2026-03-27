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
      _ body: @escaping @Sendable (SpanHandle) async throws -> R
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
    /// The supplied parent must still be alive when this operation starts. Use this for
    /// direct parent control when you already have a long-lived workflow or manual span.
    /// If you are inside an inference or stream child span and need a later tool call,
    /// capture `span.handoff()` or use `span.withToolParent(...)` before the child span ends.
    public func under(_ parent: SpanHandle) -> Self {
      var copy = self
      copy.parentSpan = parent
      return copy
    }

    /// Executes the operation, ignoring the active span handle.
    ///
    /// Use this overload when you only need automatic span creation and error recording,
    /// but do not need to add custom events or attributes.
    ///
    /// - Parameter body: An async closure that performs the work.
    /// - Returns: The result of the body.
    /// - Throws: Any error thrown by `body`, with error state recorded on the span.
    @discardableResult
    public func run<R: Sendable>(_ body: @escaping @Sendable () async throws -> R) async rethrows -> R {
      try await run { _ in
        try await body()
      }
    }

    /// Executes the operation with the active Terra span handle.
    ///
    /// This overload passes a `SpanHandle` to the body so you can record events,
    /// attributes, and streaming metrics on the child span while it is alive.
    /// The handle is closure-scoped; if later tool work must outlive this child closure,
    /// capture a deferred parent with `handoff()` or `withToolParent(...)` from the handle
    /// before returning.
    ///
    /// - Parameter body: An async closure that receives a `SpanHandle` and performs the work.
    /// - Returns: The result of the body, propagated unchanged.
    /// - Throws: Any error thrown by `body`, with error state recorded on the span.
    @discardableResult
    public func run<R: Sendable>(_ body: @escaping @Sendable (SpanHandle) async throws -> R) async rethrows -> R {
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
      _ body: @escaping @Sendable (SpanHandle) async throws -> R
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
  /// and supports recording token usage and custom events via the `SpanHandle`.
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

  /// Creates a streaming inference operation for a model call with token-by-token streaming.
  ///
  /// Use this factory method when making streaming calls where tokens are received
  /// incrementally. The resulting `Operation` creates a span that records chunk events,
  /// time-to-first-token, and total output token counts. Those final stream metrics are
  /// written when the stream closure returns or throws. If a tool call is emitted
  /// mid-stream but executed later, capture a handoff from the streaming `SpanHandle`
  /// before the closure exits and run the tool under that wider parent.
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
  /// you want the trace to correlate with upstream agent/tooling records. For deferred
  /// tool work discovered inside an inference or stream child span, prefer
  /// `try span.handoff().tool(...)` or `span.withToolParent(...)` rather than storing
  /// the child span itself past closure return.
  public static func tool(
    _ name: String,
    callId: String,
    type: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil
  ) -> Operation {
    Operation(operation: .tool(.init(name: name, callId: callId, type: type, provider: provider, runtime: runtime)))
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
    _ body: @escaping @Sendable (SpanHandle) async throws -> R
  ) async rethrows -> R {
    @Sendable func runWithCurrentSpan(
      fallbackName: String,
      _ body: @escaping @Sendable (SpanHandle) async throws -> R
    ) async throws -> R {
      if let current = Terra.currentSpan() {
        return try await body(current)
      }

      let guidance = """
      Terra could not expose the active span for \(fallbackName). This indicates a Terra context propagation bug, not valid SDK usage.
      Use Terra.workflow(...) or Terra.startSpan(...) for explicit parent control, and report this path if it reproduces.
      """
      assertionFailure(guidance)
      let invalidHandle = Terra._invalidSpanHandle(
        guidance: guidance
      )
      return try await body(invalidHandle)
    }

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
      return try await call.execute {
        try await runWithCurrentSpan(fallbackName: Terra.SpanNames.inference, body)
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
      return try await call.execute {
        try await runWithCurrentSpan(fallbackName: Terra.SpanNames.inference, body)
      }

    case .embed(let operation):
      var call = embedding(model: operation.model, inputCount: operation.inputCount)
      if let parent { call = call.under(parent) }
      if capturePolicy == .includeContent { call = call.includeContent() }
      if let provider = operation.provider { call = call.provider(provider.rawValue) }
      if let runtime = operation.runtime { call = call.runtime(runtime.rawValue) }
      if !attributes.isEmpty { call = call.attributes { _merge(attributes, into: &$0) } }
      return try await call.execute {
        try await runWithCurrentSpan(fallbackName: Terra.SpanNames.embedding, body)
      }

    case .agent(let operation):
      var call = agent(name: operation.name, id: operation.id)
      if let parent { call = call.under(parent) }
      if capturePolicy == .includeContent { call = call.includeContent() }
      if let provider = operation.provider { call = call.provider(provider.rawValue) }
      if let runtime = operation.runtime { call = call.runtime(runtime.rawValue) }
      if !attributes.isEmpty { call = call.attributes { _merge(attributes, into: &$0) } }
      return try await call.execute {
        try await runWithCurrentSpan(fallbackName: Terra.SpanNames.agentInvocation, body)
      }

    case .tool(let operation):
      var call = tool(name: operation.name, callId: operation.callId, type: operation.type)
      if let parent { call = call.under(parent) }
      if capturePolicy == .includeContent { call = call.includeContent() }
      if let provider = operation.provider { call = call.provider(provider.rawValue) }
      if let runtime = operation.runtime { call = call.runtime(runtime.rawValue) }
      if !attributes.isEmpty { call = call.attributes { _merge(attributes, into: &$0) } }
      return try await call.execute {
        try await runWithCurrentSpan(fallbackName: Terra.SpanNames.toolExecution, body)
      }

    case .safety(let operation):
      var call = safetyCheck(name: operation.name, subject: operation.subject)
      if let parent { call = call.under(parent) }
      if capturePolicy == .includeContent { call = call.includeContent() }
      if let provider = operation.provider { call = call.provider(provider.rawValue) }
      if let runtime = operation.runtime { call = call.runtime(runtime.rawValue) }
      if !attributes.isEmpty { call = call.attributes { _merge(attributes, into: &$0) } }
      return try await call.execute {
        try await runWithCurrentSpan(fallbackName: Terra.SpanNames.safetyCheck, body)
      }
    }
  }
}
