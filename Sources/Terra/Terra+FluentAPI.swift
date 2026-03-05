import Foundation
import OpenTelemetryApi

extension Terra {
  package enum TelemetryAttributeValue: Sendable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
  }

  package protocol TelemetryValue: Sendable {
    var telemetryAttributeValue: TelemetryAttributeValue { get }
  }

  package struct AttributeKey<Value: TelemetryValue>: Sendable, Hashable {
    package let name: String

    package init(_ name: String) {
      self.name = name
    }
  }

  package struct AttributeBag: Sendable, Hashable {
    var values: [String: TelemetryAttributeValue]

    package init() {
      values = [:]
    }

    package mutating func set<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) {
      values[key.name] = value.telemetryAttributeValue
    }
  }

  package protocol TerraEvent: Sendable {
    static var name: StaticString { get }
    func encode(into attributes: inout AttributeBag)
  }
}

extension String: Terra.TelemetryValue {
  package var telemetryAttributeValue: Terra.TelemetryAttributeValue { .string(self) }
}

extension Int: Terra.TelemetryValue {
  package var telemetryAttributeValue: Terra.TelemetryAttributeValue { .int(self) }
}

extension Double: Terra.TelemetryValue {
  package var telemetryAttributeValue: Terra.TelemetryAttributeValue { .double(self) }
}

extension Bool: Terra.TelemetryValue {
  package var telemetryAttributeValue: Terra.TelemetryAttributeValue { .bool(self) }
}

extension Terra.AttributeBag {
  var openTelemetryAttributes: [String: AttributeValue] {
    values.mapValues {
      switch $0 {
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
}

private enum _RuntimeTarget: Sendable {
  case shared
  case session(Terra.Session)

  func withSession<R>(
    _ body: @Sendable (Terra.Session) async throws -> R
  ) async rethrows -> R {
    let session: Terra.Session
    switch self {
    case .shared:
      session = await Terra._sharedSession()
    case .session(let value):
      session = value
    }
    return try await body(session)
  }
}

extension Terra {
  private actor SharedSessionStore {
    private var shared = Session()

    func current() -> Session {
      shared
    }

    func replace(with session: Session) {
      shared = session
    }
  }

  private static let sharedSessionStore = SharedSessionStore()

  static func _sharedSession() async -> Session {
    await sharedSessionStore.current()
  }

  static func _replaceSharedSession(_ session: Session) async {
    await sharedSessionStore.replace(with: session)
  }

  @available(*, deprecated, message: "Use Terra.inference(model:) { } or Terra.Session() directly.")
  package static func shared() async -> Session {
    await _sharedSession()
  }

  package static func inference(model: String, prompt: String? = nil) -> InferenceCall {
    inference(.chat(model: model, prompt: prompt))
  }

  package static func inference(_ request: InferenceRequest) -> InferenceCall {
    InferenceCall(runtime: .shared, request: request)
  }

  package static func stream(model: String, prompt: String? = nil) -> StreamingCall {
    stream(.chat(model: model, prompt: prompt))
  }

  package static func stream(_ request: StreamingRequest) -> StreamingCall {
    StreamingCall(runtime: .shared, request: request)
  }

  package static func embedding(model: String, inputCount: Int? = nil) -> EmbeddingCall {
    embedding(.init(model: model, inputCount: inputCount))
  }

  package static func embedding(_ request: EmbeddingRequest) -> EmbeddingCall {
    EmbeddingCall(runtime: .shared, request: request)
  }

  package static func agent(name: String, id: String? = nil) -> AgentCall {
    agent(.init(name: name, id: id))
  }

  package static func agent(_ request: AgentRequest) -> AgentCall {
    AgentCall(runtime: .shared, request: request)
  }

  package static func tool(name: String, callID: String, type: String? = nil) -> ToolCall {
    tool(.init(name: name, callID: callID, type: type))
  }

  package static func tool(_ request: ToolRequest) -> ToolCall {
    ToolCall(runtime: .shared, request: request)
  }

  package static func safetyCheck(name: String, subject: String? = nil) -> SafetyCheckCall {
    safetyCheck(.init(name: name, subject: subject))
  }

  package static func safetyCheck(_ request: SafetyCheckRequest) -> SafetyCheckCall {
    SafetyCheckCall(runtime: .shared, request: request)
  }

  // MARK: - Closure-first factories (v3)

  @discardableResult
  package static func inference<R>(
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
    ) { (_: InferenceTrace) in
      try await body()
    }
  }

  @discardableResult
  package static func inference<R>(
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
    return try await call.execute(body)
  }

  @discardableResult
  package static func stream<R>(
    model: String,
    prompt: String? = nil,
    provider: String? = nil,
    runtime: String? = nil,
    temperature: Double? = nil,
    maxOutputTokens: Int? = nil,
    _ body: @Sendable () async throws -> R
  ) async rethrows -> R {
    try await stream(
      model: model,
      prompt: prompt,
      provider: provider,
      runtime: runtime,
      temperature: temperature,
      maxOutputTokens: maxOutputTokens
    ) { (_: StreamingTrace) in
      try await body()
    }
  }

  @discardableResult
  package static func stream<R>(
    model: String,
    prompt: String? = nil,
    provider: String? = nil,
    runtime: String? = nil,
    temperature: Double? = nil,
    maxOutputTokens: Int? = nil,
    _ body: @Sendable (StreamingTrace) async throws -> R
  ) async rethrows -> R {
    var call = stream(model: model, prompt: prompt)
    if let provider { call = call.provider(provider) }
    if let runtime { call = call.runtime(runtime) }
    if let temperature { call = call.temperature(temperature) }
    if let maxOutputTokens { call = call.maxOutputTokens(maxOutputTokens) }
    return try await call.execute(body)
  }

  @discardableResult
  package static func embedding<R>(
    model: String,
    inputCount: Int? = nil,
    provider: String? = nil,
    runtime: String? = nil,
    _ body: @Sendable () async throws -> R
  ) async rethrows -> R {
    try await embedding(
      model: model,
      inputCount: inputCount,
      provider: provider,
      runtime: runtime
    ) { (_: EmbeddingTrace) in
      try await body()
    }
  }

  @discardableResult
  package static func embedding<R>(
    model: String,
    inputCount: Int? = nil,
    provider: String? = nil,
    runtime: String? = nil,
    _ body: @Sendable (EmbeddingTrace) async throws -> R
  ) async rethrows -> R {
    var call = embedding(model: model, inputCount: inputCount)
    if let provider { call = call.provider(provider) }
    if let runtime { call = call.runtime(runtime) }
    return try await call.execute(body)
  }

  @discardableResult
  package static func agent<R>(
    name: String,
    id: String? = nil,
    provider: String? = nil,
    runtime: String? = nil,
    _ body: @Sendable () async throws -> R
  ) async rethrows -> R {
    try await agent(
      name: name,
      id: id,
      provider: provider,
      runtime: runtime
    ) { (_: AgentTrace) in
      try await body()
    }
  }

  @discardableResult
  package static func agent<R>(
    name: String,
    id: String? = nil,
    provider: String? = nil,
    runtime: String? = nil,
    _ body: @Sendable (AgentTrace) async throws -> R
  ) async rethrows -> R {
    var call = agent(name: name, id: id)
    if let provider { call = call.provider(provider) }
    if let runtime { call = call.runtime(runtime) }
    return try await call.execute(body)
  }

  @discardableResult
  package static func tool<R>(
    name: String,
    callID: String,
    type: String? = nil,
    provider: String? = nil,
    runtime: String? = nil,
    _ body: @Sendable () async throws -> R
  ) async rethrows -> R {
    try await tool(
      name: name,
      callID: callID,
      type: type,
      provider: provider,
      runtime: runtime
    ) { (_: ToolTrace) in
      try await body()
    }
  }

  @discardableResult
  package static func tool<R>(
    name: String,
    callID: String,
    type: String? = nil,
    provider: String? = nil,
    runtime: String? = nil,
    _ body: @Sendable (ToolTrace) async throws -> R
  ) async rethrows -> R {
    var call = tool(name: name, callID: callID, type: type)
    if let provider { call = call.provider(provider) }
    if let runtime { call = call.runtime(runtime) }
    return try await call.execute(body)
  }

  @discardableResult
  package static func safetyCheck<R>(
    name: String,
    subject: String? = nil,
    provider: String? = nil,
    runtime: String? = nil,
    _ body: @Sendable () async throws -> R
  ) async rethrows -> R {
    try await safetyCheck(
      name: name,
      subject: subject,
      provider: provider,
      runtime: runtime
    ) { (_: SafetyCheckTrace) in
      try await body()
    }
  }

  @discardableResult
  package static func safetyCheck<R>(
    name: String,
    subject: String? = nil,
    provider: String? = nil,
    runtime: String? = nil,
    _ body: @Sendable (SafetyCheckTrace) async throws -> R
  ) async rethrows -> R {
    var call = safetyCheck(name: name, subject: subject)
    if let provider { call = call.provider(provider) }
    if let runtime { call = call.runtime(runtime) }
    return try await call.execute(body)
  }
}

extension Terra {
  package actor Session: Sendable {
    package init() {}

    package nonisolated func inference(model: String, prompt: String? = nil) -> InferenceCall {
      inference(.chat(model: model, prompt: prompt))
    }

    package nonisolated func inference(_ request: InferenceRequest) -> InferenceCall {
      InferenceCall(runtime: .session(self), request: request)
    }

    package nonisolated func stream(model: String, prompt: String? = nil) -> StreamingCall {
      stream(.chat(model: model, prompt: prompt))
    }

    package nonisolated func stream(_ request: StreamingRequest) -> StreamingCall {
      StreamingCall(runtime: .session(self), request: request)
    }

    package nonisolated func embedding(model: String, inputCount: Int? = nil) -> EmbeddingCall {
      embedding(.init(model: model, inputCount: inputCount))
    }

    package nonisolated func embedding(_ request: EmbeddingRequest) -> EmbeddingCall {
      EmbeddingCall(runtime: .session(self), request: request)
    }

    package nonisolated func agent(name: String, id: String? = nil) -> AgentCall {
      agent(.init(name: name, id: id))
    }

    package nonisolated func agent(_ request: AgentRequest) -> AgentCall {
      AgentCall(runtime: .session(self), request: request)
    }

    package nonisolated func tool(name: String, callID: String, type: String? = nil) -> ToolCall {
      tool(.init(name: name, callID: callID, type: type))
    }

    package nonisolated func tool(_ request: ToolRequest) -> ToolCall {
      ToolCall(runtime: .session(self), request: request)
    }

    package nonisolated func safetyCheck(name: String, subject: String? = nil) -> SafetyCheckCall {
      safetyCheck(.init(name: name, subject: subject))
    }

    package nonisolated func safetyCheck(_ request: SafetyCheckRequest) -> SafetyCheckCall {
      SafetyCheckCall(runtime: .session(self), request: request)
    }

    func runInference<R>(
      request: InferenceRequest,
      attributes: AttributeBag,
      _ body: @Sendable (InferenceTrace) async throws -> R
    ) async rethrows -> R {
      Terra.agentContext?.recordModel(request.model)
      return try await Terra.withInferenceSpan(request) { scope in
        if !attributes.values.isEmpty {
          scope.setAttributes(attributes.openTelemetryAttributes)
        }
        let trace = InferenceTrace(scope: scope)
        let result = try await body(trace)
        if let traceable = result as? any TerraTraceable {
          if let usage = traceable.terraTokenUsage {
            trace.tokens(input: usage.input, output: usage.output)
          }
          if let responseModel = traceable.terraResponseModel {
            trace.responseModel(responseModel)
          }
        }
        return result
      }
    }

    func runStreaming<R>(
      request: StreamingRequest,
      attributes: AttributeBag,
      _ body: @Sendable (StreamingTrace) async throws -> R
    ) async rethrows -> R {
      Terra.agentContext?.recordModel(request.model)
      return try await Terra.withStreamingInferenceSpan(request) { scope in
        if !attributes.values.isEmpty {
          scope.setAttributes(attributes.openTelemetryAttributes)
        }
        return try await body(StreamingTrace(scope: scope))
      }
    }

    func runEmbedding<R>(
      request: EmbeddingRequest,
      attributes: AttributeBag,
      _ body: @Sendable (EmbeddingTrace) async throws -> R
    ) async rethrows -> R {
      return try await Terra.withEmbeddingSpan(request) { scope in
        if !attributes.values.isEmpty {
          scope.setAttributes(attributes.openTelemetryAttributes)
        }
        return try await body(EmbeddingTrace(scope: scope))
      }
    }

    func runAgent<R>(
      request: AgentRequest,
      attributes: AttributeBag,
      _ body: @Sendable (AgentTrace) async throws -> R
    ) async rethrows -> R {
      let context = Terra.AgentContext()
      return try await Terra.$agentContext.withValue(context) {
        try await Terra.withAgentInvocationSpan(agent: request) { scope in
          if !attributes.values.isEmpty {
            scope.setAttributes(attributes.openTelemetryAttributes)
          }
          let result = try await body(AgentTrace(scope: scope))
          let snapshot = context.snapshot()
          scope.setAttributes([
            "terra.agent.tools_used": .string(snapshot.toolsUsed.sorted().joined(separator: ",")),
            "terra.agent.models_used": .string(snapshot.modelsUsed.sorted().joined(separator: ",")),
            "terra.agent.inference_count": .int(snapshot.inferenceCount),
            "terra.agent.tool_call_count": .int(snapshot.toolCallCount),
          ])
          return result
        }
      }
    }

    func runTool<R>(
      request: ToolRequest,
      attributes: AttributeBag,
      _ body: @Sendable (ToolTrace) async throws -> R
    ) async rethrows -> R {
      Terra.agentContext?.recordTool(request.name)
      return try await Terra.withToolExecutionSpan(tool: request) { scope in
        if !attributes.values.isEmpty {
          scope.setAttributes(attributes.openTelemetryAttributes)
        }
        return try await body(ToolTrace(scope: scope))
      }
    }

    func runSafetyCheck<R>(
      request: SafetyCheckRequest,
      attributes: AttributeBag,
      _ body: @Sendable (SafetyCheckTrace) async throws -> R
    ) async rethrows -> R {
      return try await Terra.withSafetyCheckSpan(request) { scope in
        if !attributes.values.isEmpty {
          scope.setAttributes(attributes.openTelemetryAttributes)
        }
        return try await body(SafetyCheckTrace(scope: scope))
      }
    }
  }
}

private struct _CallMetadata: Sendable {
  var includeContent: Bool = false
  var attributes: Terra.AttributeBag = .init()
}

extension Terra {
  package struct InferenceCall: Sendable {
    private let runtime: _RuntimeTarget
    private var request: InferenceRequest
    private var metadata = _CallMetadata()

    fileprivate init(runtime: _RuntimeTarget, request: InferenceRequest) {
      self.runtime = runtime
      self.request = request
    }

    package func includeContent() -> Self {
      var copy = self
      copy.metadata.includeContent = true
      return copy
    }

    @available(*, deprecated, message: "Use includeContent() for per-call content capture.")
    package func capture(_ intent: CaptureIntent) -> Self {
      switch intent {
      case .default:
        return self
      case .optIn:
        return includeContent()
      }
    }

    package func runtime(_ value: String) -> Self {
      attribute(.init(Keys.Terra.runtime), value)
    }

    package func provider(_ value: String) -> Self {
      attribute(.init(Keys.GenAI.providerName), value)
    }

    package func responseModel(_ value: String) -> Self {
      attribute(.init(Keys.GenAI.responseModel), value)
    }

    package func tokens(input: Int? = nil, output: Int? = nil) -> Self {
      var copy = self
      if let input {
        copy = copy.attribute(.init(Keys.GenAI.usageInputTokens), input)
      }
      if let output {
        copy = copy.attribute(.init(Keys.GenAI.usageOutputTokens), output)
      }
      return copy
    }

    package func temperature(_ value: Double) -> Self {
      var copy = self
      copy.request.temperature = value
      return copy
    }

    package func maxOutputTokens(_ value: Int) -> Self {
      var copy = self
      copy.request.maxOutputTokens = value
      return copy
    }

    package func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self {
      var copy = self
      copy.metadata.attributes.set(key, value)
      return copy
    }

    package func attributes(_ block: (inout AttributeBag) -> Void) -> Self {
      var copy = self
      var bag = copy.metadata.attributes
      block(&bag)
      copy.metadata.attributes = bag
      return copy
    }

    @discardableResult
    package func execute<R>(_ body: @Sendable () async throws -> R) async rethrows -> R {
      try await execute { _ in
        try await body()
      }
    }

    @discardableResult
    package func execute<R>(_ body: @Sendable (InferenceTrace) async throws -> R) async rethrows -> R {
      let request: InferenceRequest = {
        var copy = self.request
        if metadata.includeContent {
          copy.promptCapture = .optIn
        }
        return copy
      }()
      return try await runtime.withSession { session in
        try await session.runInference(request: request, attributes: metadata.attributes, body)
      }
    }

    @available(*, deprecated, message: "Use execute(_:) instead.")
    @discardableResult
    package func run<R>(_ body: @Sendable () async throws -> R) async rethrows -> R {
      try await execute(body)
    }

    @available(*, deprecated, message: "Use execute(_:) instead.")
    @discardableResult
    package func run<R>(_ body: @Sendable (InferenceTrace) async throws -> R) async rethrows -> R {
      try await execute(body)
    }
  }

  package struct StreamingCall: Sendable {
    private let runtime: _RuntimeTarget
    private var request: StreamingRequest
    private var metadata = _CallMetadata()

    fileprivate init(runtime: _RuntimeTarget, request: StreamingRequest) {
      self.runtime = runtime
      self.request = request
    }

    package func includeContent() -> Self {
      var copy = self
      copy.metadata.includeContent = true
      return copy
    }

    @available(*, deprecated, message: "Use includeContent() for per-call content capture.")
    package func capture(_ intent: CaptureIntent) -> Self {
      switch intent {
      case .default:
        return self
      case .optIn:
        return includeContent()
      }
    }

    package func runtime(_ value: String) -> Self {
      attribute(.init(Keys.Terra.runtime), value)
    }

    package func provider(_ value: String) -> Self {
      attribute(.init(Keys.GenAI.providerName), value)
    }

    package func temperature(_ value: Double) -> Self {
      var copy = self
      copy.request.temperature = value
      return copy
    }

    package func maxOutputTokens(_ value: Int) -> Self {
      var copy = self
      copy.request.maxOutputTokens = value
      return copy
    }

    package func expectedOutputTokens(_ value: Int) -> Self {
      var copy = self
      copy.request.expectedOutputTokens = value
      return copy
    }

    package func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self {
      var copy = self
      copy.metadata.attributes.set(key, value)
      return copy
    }

    package func attributes(_ block: (inout AttributeBag) -> Void) -> Self {
      var copy = self
      var bag = copy.metadata.attributes
      block(&bag)
      copy.metadata.attributes = bag
      return copy
    }

    @discardableResult
    package func execute<R>(_ body: @Sendable () async throws -> R) async rethrows -> R {
      try await execute { _ in
        try await body()
      }
    }

    @discardableResult
    package func execute<R>(_ body: @Sendable (StreamingTrace) async throws -> R) async rethrows -> R {
      let request: StreamingRequest = {
        var copy = self.request
        if metadata.includeContent {
          copy.promptCapture = .optIn
        }
        return copy
      }()
      return try await runtime.withSession { session in
        try await session.runStreaming(request: request, attributes: metadata.attributes, body)
      }
    }

    @available(*, deprecated, message: "Use execute(_:) instead.")
    @discardableResult
    package func run<R>(_ body: @Sendable () async throws -> R) async rethrows -> R {
      try await execute(body)
    }

    @available(*, deprecated, message: "Use execute(_:) instead.")
    @discardableResult
    package func run<R>(_ body: @Sendable (StreamingTrace) async throws -> R) async rethrows -> R {
      try await execute(body)
    }
  }

  package struct EmbeddingCall: Sendable {
    private let runtime: _RuntimeTarget
    private var request: EmbeddingRequest
    private var metadata = _CallMetadata()

    fileprivate init(runtime: _RuntimeTarget, request: EmbeddingRequest) {
      self.runtime = runtime
      self.request = request
    }

    package func includeContent() -> Self {
      var copy = self
      copy.metadata.includeContent = true
      return copy
    }

    @available(*, deprecated, message: "Use includeContent() for per-call content capture.")
    package func capture(_ intent: CaptureIntent) -> Self {
      switch intent {
      case .default:
        return self
      case .optIn:
        return includeContent()
      }
    }

    package func runtime(_ value: String) -> Self {
      attribute(.init(Keys.Terra.runtime), value)
    }

    package func provider(_ value: String) -> Self {
      attribute(.init(Keys.GenAI.providerName), value)
    }

    package func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self {
      var copy = self
      copy.metadata.attributes.set(key, value)
      return copy
    }

    package func attributes(_ block: (inout AttributeBag) -> Void) -> Self {
      var copy = self
      var bag = copy.metadata.attributes
      block(&bag)
      copy.metadata.attributes = bag
      return copy
    }

    @discardableResult
    package func execute<R>(_ body: @Sendable () async throws -> R) async rethrows -> R {
      try await execute { _ in
        try await body()
      }
    }

    @discardableResult
    package func execute<R>(_ body: @Sendable (EmbeddingTrace) async throws -> R) async rethrows -> R {
      try await runtime.withSession { session in
        try await session.runEmbedding(request: request, attributes: metadata.attributes, body)
      }
    }

    @available(*, deprecated, message: "Use execute(_:) instead.")
    @discardableResult
    package func run<R>(_ body: @Sendable () async throws -> R) async rethrows -> R {
      try await execute(body)
    }

    @available(*, deprecated, message: "Use execute(_:) instead.")
    @discardableResult
    package func run<R>(_ body: @Sendable (EmbeddingTrace) async throws -> R) async rethrows -> R {
      try await execute(body)
    }
  }

  package struct AgentCall: Sendable {
    private let runtime: _RuntimeTarget
    private var request: AgentRequest
    private var metadata = _CallMetadata()

    fileprivate init(runtime: _RuntimeTarget, request: AgentRequest) {
      self.runtime = runtime
      self.request = request
    }

    package func includeContent() -> Self {
      var copy = self
      copy.metadata.includeContent = true
      return copy
    }

    @available(*, deprecated, message: "Use includeContent() for per-call content capture.")
    package func capture(_ intent: CaptureIntent) -> Self {
      switch intent {
      case .default:
        return self
      case .optIn:
        return includeContent()
      }
    }

    package func runtime(_ value: String) -> Self {
      attribute(.init(Keys.Terra.runtime), value)
    }

    package func provider(_ value: String) -> Self {
      attribute(.init(Keys.GenAI.providerName), value)
    }

    package func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self {
      var copy = self
      copy.metadata.attributes.set(key, value)
      return copy
    }

    package func attributes(_ block: (inout AttributeBag) -> Void) -> Self {
      var copy = self
      var bag = copy.metadata.attributes
      block(&bag)
      copy.metadata.attributes = bag
      return copy
    }

    @discardableResult
    package func execute<R>(_ body: @Sendable () async throws -> R) async rethrows -> R {
      try await execute { _ in
        try await body()
      }
    }

    @discardableResult
    package func execute<R>(_ body: @Sendable (AgentTrace) async throws -> R) async rethrows -> R {
      try await runtime.withSession { session in
        try await session.runAgent(request: request, attributes: metadata.attributes, body)
      }
    }

    @available(*, deprecated, message: "Use execute(_:) instead.")
    @discardableResult
    package func run<R>(_ body: @Sendable () async throws -> R) async rethrows -> R {
      try await execute(body)
    }

    @available(*, deprecated, message: "Use execute(_:) instead.")
    @discardableResult
    package func run<R>(_ body: @Sendable (AgentTrace) async throws -> R) async rethrows -> R {
      try await execute(body)
    }
  }

  package struct ToolCall: Sendable {
    private let runtime: _RuntimeTarget
    private var request: ToolRequest
    private var metadata = _CallMetadata()

    fileprivate init(runtime: _RuntimeTarget, request: ToolRequest) {
      self.runtime = runtime
      self.request = request
    }

    package func includeContent() -> Self {
      var copy = self
      copy.metadata.includeContent = true
      return copy
    }

    @available(*, deprecated, message: "Use includeContent() for per-call content capture.")
    package func capture(_ intent: CaptureIntent) -> Self {
      switch intent {
      case .default:
        return self
      case .optIn:
        return includeContent()
      }
    }

    package func runtime(_ value: String) -> Self {
      attribute(.init(Keys.Terra.runtime), value)
    }

    package func provider(_ value: String) -> Self {
      attribute(.init(Keys.GenAI.providerName), value)
    }

    package func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self {
      var copy = self
      copy.metadata.attributes.set(key, value)
      return copy
    }

    package func attributes(_ block: (inout AttributeBag) -> Void) -> Self {
      var copy = self
      var bag = copy.metadata.attributes
      block(&bag)
      copy.metadata.attributes = bag
      return copy
    }

    @discardableResult
    package func execute<R>(_ body: @Sendable () async throws -> R) async rethrows -> R {
      try await execute { _ in
        try await body()
      }
    }

    @discardableResult
    package func execute<R>(_ body: @Sendable (ToolTrace) async throws -> R) async rethrows -> R {
      try await runtime.withSession { session in
        try await session.runTool(request: request, attributes: metadata.attributes, body)
      }
    }

    @available(*, deprecated, message: "Use execute(_:) instead.")
    @discardableResult
    package func run<R>(_ body: @Sendable () async throws -> R) async rethrows -> R {
      try await execute(body)
    }

    @available(*, deprecated, message: "Use execute(_:) instead.")
    @discardableResult
    package func run<R>(_ body: @Sendable (ToolTrace) async throws -> R) async rethrows -> R {
      try await execute(body)
    }
  }

  package struct SafetyCheckCall: Sendable {
    private let runtime: _RuntimeTarget
    private var request: SafetyCheckRequest
    private var metadata = _CallMetadata()

    fileprivate init(runtime: _RuntimeTarget, request: SafetyCheckRequest) {
      self.runtime = runtime
      self.request = request
    }

    package func includeContent() -> Self {
      var copy = self
      copy.metadata.includeContent = true
      return copy
    }

    @available(*, deprecated, message: "Use includeContent() for per-call content capture.")
    package func capture(_ intent: CaptureIntent) -> Self {
      switch intent {
      case .default:
        return self
      case .optIn:
        return includeContent()
      }
    }

    package func runtime(_ value: String) -> Self {
      attribute(.init(Keys.Terra.runtime), value)
    }

    package func provider(_ value: String) -> Self {
      attribute(.init(Keys.GenAI.providerName), value)
    }

    package func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self {
      var copy = self
      copy.metadata.attributes.set(key, value)
      return copy
    }

    package func attributes(_ block: (inout AttributeBag) -> Void) -> Self {
      var copy = self
      var bag = copy.metadata.attributes
      block(&bag)
      copy.metadata.attributes = bag
      return copy
    }

    @discardableResult
    package func execute<R>(_ body: @Sendable () async throws -> R) async rethrows -> R {
      try await execute { _ in
        try await body()
      }
    }

    @discardableResult
    package func execute<R>(_ body: @Sendable (SafetyCheckTrace) async throws -> R) async rethrows -> R {
      let request: SafetyCheckRequest = {
        var copy = self.request
        if metadata.includeContent {
          copy.subjectCapture = .optIn
        }
        return copy
      }()
      return try await runtime.withSession { session in
        try await session.runSafetyCheck(request: request, attributes: metadata.attributes, body)
      }
    }

    @available(*, deprecated, message: "Use execute(_:) instead.")
    @discardableResult
    package func run<R>(_ body: @Sendable () async throws -> R) async rethrows -> R {
      try await execute(body)
    }

    @available(*, deprecated, message: "Use execute(_:) instead.")
    @discardableResult
    package func run<R>(_ body: @Sendable (SafetyCheckTrace) async throws -> R) async rethrows -> R {
      try await execute(body)
    }
  }
}

extension Terra.TelemetryAttributeValue {
  var openTelemetryValue: AttributeValue {
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
