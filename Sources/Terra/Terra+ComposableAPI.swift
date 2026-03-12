import Foundation

extension Terra {
  public enum CapturePolicy: Sendable, Hashable {
    case `default`
    case includeContent
  }

  public protocol ScalarValue: Sendable {
    var traceScalar: TraceScalar { get }
  }

  public enum TraceScalar: Sendable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
  }

  public struct TraceKey<Value: ScalarValue>: Sendable, Hashable {
    public let name: String

    public init(_ name: String) {
      self.name = name
    }
  }

  public struct TraceAttribute: Sendable, Hashable {
    public let name: String
    public let value: TraceScalar

    public init(name: String, value: TraceScalar) {
      self.name = name
      self.value = value
    }
  }

  public enum Metadata: Sendable, Hashable {
    case event(String)
    case attribute(TraceAttribute)
  }

  @resultBuilder
  public enum MetadataBuilder {
    public static func buildBlock(_ components: [Metadata]...) -> [Metadata] {
      components.flatMap { $0 }
    }

    public static func buildExpression(_ expression: Metadata) -> [Metadata] {
      [expression]
    }

    public static func buildExpression(_ expression: [Metadata]) -> [Metadata] {
      expression
    }

    public static func buildOptional(_ component: [Metadata]?) -> [Metadata] {
      component ?? []
    }

    public static func buildEither(first component: [Metadata]) -> [Metadata] {
      component
    }

    public static func buildEither(second component: [Metadata]) -> [Metadata] {
      component
    }

    public static func buildArray(_ components: [[Metadata]]) -> [Metadata] {
      components.flatMap { $0 }
    }

    public static func buildLimitedAvailability(_ component: [Metadata]) -> [Metadata] {
      component
    }
  }

  public struct TelemetryContext: Sendable, Hashable {
    public enum Operation: String, Sendable, Hashable {
      case inference
      case streaming
      case embedding
      case agent
      case tool
      case safety
    }

    public let operation: Operation
    public let model: ModelID?
    public let name: String?
    public let provider: ProviderID?
    public let runtime: RuntimeID?
    public let capturePolicy: CapturePolicy

    public init(
      operation: Operation,
      model: ModelID? = nil,
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

  public protocol TelemetryEngine: Sendable {
    func run<R: Sendable>(
      context: TelemetryContext,
      attributes: [TraceAttribute],
      _ body: @escaping @Sendable (TraceHandle) async throws -> R
    ) async throws -> R
  }

  public static func event(_ name: String) -> Metadata {
    .event(name)
  }

  public static func attr<Value: ScalarValue>(_ key: TraceKey<Value>, _ value: Value) -> Metadata {
    .attribute(.init(name: key.name, value: value.traceScalar))
  }

  package enum TraceKeys {
    static let runtime = TraceKey<RuntimeID>("terra.runtime")
    static let provider = TraceKey<ProviderID>("gen_ai.provider.name")
    static let responseModel = TraceKey<ModelID>("gen_ai.response.model")
    static let inputTokens = TraceKey<Int>("gen_ai.usage.input_tokens")
    static let outputTokens = TraceKey<Int>("gen_ai.usage.output_tokens")
    static let temperature = TraceKey<Double>("gen_ai.request.temperature")
    static let maxOutputTokens = TraceKey<Int>("gen_ai.request.max_tokens")
  }

  public struct TraceHandle: Sendable {
    private let onEvent: @Sendable (String) -> Void
    private let onAttribute: @Sendable (String, TraceScalar) -> Void
    private let onError: @Sendable (any Error) -> Void
    private let onTokens: @Sendable (Int?, Int?) -> Void
    private let onResponseModel: @Sendable (ModelID) -> Void
    private let onChunk: @Sendable (Int) -> Void
    private let onOutputTokens: @Sendable (Int) -> Void
    private let onFirstToken: @Sendable () -> Void

    public init(
      onEvent: @escaping @Sendable (String) -> Void,
      onAttribute: @escaping @Sendable (String, TraceScalar) -> Void,
      onError: @escaping @Sendable (any Error) -> Void,
      onTokens: @escaping @Sendable (Int?, Int?) -> Void = { _, _ in },
      onResponseModel: @escaping @Sendable (ModelID) -> Void = { _ in },
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

    @discardableResult
    public func event(_ name: String) -> Self {
      onEvent(name)
      return self
    }

    @discardableResult
    public func tag<T: CustomStringConvertible & Sendable>(_ key: StaticString, _ value: T) -> Self {
      onAttribute(key.description, .string(value.description))
      return self
    }

    @discardableResult
    public func tokens(input: Int? = nil, output: Int? = nil) -> Self {
      onTokens(input, output)
      return self
    }

    @discardableResult
    public func responseModel(_ value: ModelID) -> Self {
      onResponseModel(value)
      return self
    }

    @discardableResult
    public func chunk(_ tokens: Int = 1) -> Self {
      onChunk(tokens)
      return self
    }

    @discardableResult
    public func outputTokens(_ total: Int) -> Self {
      onOutputTokens(total)
      return self
    }

    @discardableResult
    public func firstToken() -> Self {
      onFirstToken()
      return self
    }

    public func recordError(_ error: any Error) {
      onError(error)
    }
  }

  public struct Operation: Sendable {
    private var operation: _Operation
    private var capturePolicy: CapturePolicy = .default
    private var attributes: [_TraceAttribute] = []
    private var metadataEntries: [Metadata] = []

    fileprivate init(operation: _Operation) {
      self.operation = operation
    }

    public func capture(_ policy: CapturePolicy) -> Self {
      var copy = self
      copy.capturePolicy = policy
      return copy
    }

    @discardableResult
    public func run<R: Sendable>(_ body: @escaping @Sendable () async throws -> R) async rethrows -> R {
      try await run { _ in
        try await body()
      }
    }

    @discardableResult
    public func run<R: Sendable>(_ body: @escaping @Sendable (TraceHandle) async throws -> R) async rethrows -> R {
      let attributes = _mergedAttributes()
      let events = _metadataEvents()
      return try await _run(operation: operation, capturePolicy: capturePolicy, attributes: attributes) { handle in
        for event in events {
          _ = handle.event(event)
        }
        return try await body(handle)
      }
    }

    @discardableResult
    public func run<R: Sendable, Engine: TelemetryEngine>(
      using engine: Engine,
      _ body: @escaping @Sendable () async throws -> R
    ) async throws -> R {
      try await run(using: engine) { _ in
        try await body()
      }
    }

    @discardableResult
    public func run<R: Sendable, Engine: TelemetryEngine>(
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

  public static func infer(
    _ model: ModelID,
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

  public static func stream(
    _ model: ModelID,
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

  public static func embed(
    _ model: ModelID,
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

  public static func agent(
    _ name: String,
    id: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil
  ) -> Operation {
    Operation(operation: .agent(.init(name: name, id: id, provider: provider, runtime: runtime)))
  }

  public static func tool(
    _ name: String,
    callID: ToolCallID = .init(),
    type: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil
  ) -> Operation {
    Operation(operation: .tool(.init(name: name, callID: callID, type: type, provider: provider, runtime: runtime)))
  }

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
  public var traceScalar: Terra.TraceScalar { .string(self) }
}

extension Int: Terra.ScalarValue {
  public var traceScalar: Terra.TraceScalar { .int(self) }
}

extension Double: Terra.ScalarValue {
  public var traceScalar: Terra.TraceScalar { .double(self) }
}

extension Bool: Terra.ScalarValue {
  public var traceScalar: Terra.TraceScalar { .bool(self) }
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
    var model: ModelID
    var prompt: String?
    var provider: ProviderID?
    var runtime: RuntimeID?
    var temperature: Double?
    var maxTokens: Int?
  }

  struct _Stream: Sendable {
    var model: ModelID
    var prompt: String?
    var provider: ProviderID?
    var runtime: RuntimeID?
    var temperature: Double?
    var maxTokens: Int?
    var expectedTokens: Int?
  }

  struct _Embed: Sendable {
    var model: ModelID
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
    var callID: ToolCallID
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
    _ body: @escaping @Sendable (TraceHandle) async throws -> R
  ) async rethrows -> R {
    switch operation {
    case .infer(let operation):
      var call = inference(model: operation.model.rawValue, prompt: operation.prompt)
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
          onResponseModel: { _ = trace.responseModel($0.rawValue) }
        )
        return try await body(handle)
      }

    case .stream(let operation):
      var call = stream(model: operation.model.rawValue, prompt: operation.prompt)
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
      var call = embedding(model: operation.model.rawValue, inputCount: operation.inputCount)
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
      var call = tool(name: operation.name, callID: operation.callID.rawValue, type: operation.type)
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
