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
    private let onResponseModel: @Sendable (String) -> Void
    private let onChunk: @Sendable (Int) -> Void
    private let onOutputTokens: @Sendable (Int) -> Void
    private let onFirstToken: @Sendable () -> Void

    fileprivate init(
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

    @discardableResult
    public func event(_ name: String) -> Self {
      onEvent(name)
      return self
    }

    @discardableResult
    public func attr<Value: ScalarValue>(_ key: TraceKey<Value>, _ value: Value) -> Self {
      onAttribute(key.name, value.traceScalar)
      return self
    }

    @discardableResult
    public func tokens(input: Int? = nil, output: Int? = nil) -> Self {
      onTokens(input, output)
      return self
    }

    @discardableResult
    public func responseModel(_ value: String) -> Self {
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

  public struct Call: Sendable {
    private var operation: _Operation
    private var capturePolicy: CapturePolicy = .default
    private var attributes: [_TraceAttribute] = []

    fileprivate init(operation: _Operation) {
      self.operation = operation
    }

    public func capture(_ policy: CapturePolicy) -> Self {
      var copy = self
      copy.capturePolicy = policy
      return copy
    }

    public func attr<Value: ScalarValue>(_ key: TraceKey<Value>, _ value: Value) -> Self {
      var copy = self
      copy.attributes.append(.init(name: key.name, value: value.traceScalar))
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
      try await _run(operation: operation, capturePolicy: capturePolicy, attributes: attributes, body)
    }
  }

  public static func infer(
    _ model: ModelID,
    prompt: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil,
    temperature: Double? = nil,
    maxTokens: Int? = nil
  ) -> Call {
    Call(operation: .infer(.init(
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
  ) -> Call {
    Call(operation: .stream(.init(
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
  ) -> Call {
    Call(operation: .embed(.init(
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
  ) -> Call {
    Call(operation: .agent(.init(name: name, id: id, provider: provider, runtime: runtime)))
  }

  public static func tool(
    _ name: String,
    callID: ToolCallID,
    type: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil
  ) -> Call {
    Call(operation: .tool(.init(name: name, callID: callID, type: type, provider: provider, runtime: runtime)))
  }

  public static func safety(
    _ name: String,
    subject: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil
  ) -> Call {
    Call(operation: .safety(.init(name: name, subject: subject, provider: provider, runtime: runtime)))
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
          onResponseModel: { _ = trace.responseModel($0) }
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
