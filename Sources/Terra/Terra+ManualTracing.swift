import Foundation
import OpenTelemetryApi

extension Terra {
  private enum _SpanContext: @unchecked Sendable {
    @TaskLocal static var current: SpanHandle?
  }

  private enum _DetachedParentEndedContext {
    @TaskLocal static var current = false
  }

  /// A sendable handle to an active Terra span.
  ///
  /// Use `SpanHandle` when span lifecycle must outlive a single closure or when
  /// you need to inspect the active Terra trace context. This keeps OpenTelemetry
  /// internals out of the public API while still exposing the operations that
  /// agentic workflows need most often.
  ///
  /// ```swift
  /// let value = try await Terra.workflow(name: "inference", id: "issue-42") { span in
  ///   span.event("started")
  ///   return "ok"
  /// }
  /// ```
  public struct SpanHandle: Sendable {
    private let storage: _SpanHandleStorage

    fileprivate init(storage: _SpanHandleStorage) {
      self.storage = storage
    }

    public var name: String { storage.name }
    public var id: String? { storage.id }
    public var traceId: String { storage.traceId }
    public var spanId: String { storage.spanId }
    public var parentId: String? { storage.parentId }
    public var isEnded: Bool { storage.isEnded }

    package var otelSpan: any Span { storage.span }

    package func attributeValue(for key: String) -> AttributeValue? {
      storage.attributeValue(for: key)
    }

    /// Records a named event on the span.
    ///
    /// Use this to annotate milestone transitions in long-running tasks so a
    /// coding agent can reconstruct workflow state from trace history.
    @discardableResult
    public func event(_ name: String) -> Self {
      storage.event(name)
      return self
    }

    /// Attaches a string attribute to the span.
    @discardableResult
    public func attribute(_ key: String, _ value: String) -> Self {
      storage.attribute(key, .string(value))
      return self
    }

    /// Attaches an integer attribute to the span.
    @discardableResult
    public func attribute(_ key: String, _ value: Int) -> Self {
      storage.attribute(key, .int(value))
      return self
    }

    /// Attaches a floating-point attribute to the span.
    @discardableResult
    public func attribute(_ key: String, _ value: Double) -> Self {
      storage.attribute(key, .double(value))
      return self
    }

    /// Attaches a boolean attribute to the span.
    @discardableResult
    public func attribute(_ key: String, _ value: Bool) -> Self {
      storage.attribute(key, .bool(value))
      return self
    }

    /// Records input and output token counts on the span.
    @discardableResult
    public func tokens(input: Int? = nil, output: Int? = nil) -> Self {
      storage.tokens(input: input, output: output)
      return self
    }

    /// Records the model identifier that produced the response.
    @discardableResult
    public func responseModel(_ value: String) -> Self {
      storage.responseModel(value)
      return self
    }

    /// Records an error on the span and marks it failed.
    public func recordError(_ error: any Error) {
      storage.recordError(error)
    }

    /// Records a named checkpoint event on the span.
    @discardableResult
    public func checkpoint(_ name: String) -> Self {
      event("checkpoint.\(name)")
    }

    /// Records a streaming chunk on the span.
    @discardableResult
    public func chunk(_ tokens: Int = 1) -> Self {
      storage.chunk(tokens)
      return self
    }

    /// Records the final streaming output token count on the span.
    @discardableResult
    public func outputTokens(_ total: Int) -> Self {
      storage.outputTokens(total)
      return self
    }

    /// Records the first-token marker on the span.
    @discardableResult
    public func firstToken() -> Self {
      storage.firstToken()
      return self
    }

    /// Ends the span if this handle owns the lifecycle.
    ///
    /// `Terra.workflow {}` owns lifecycle automatically. `Terra.currentSpan()` may return
    /// a handle for a span owned elsewhere, in which case `end()` is ignored and Terra
    /// emits guidance in debug builds.
    public func end() {
      storage.end()
    }

    /// Runs detached work while keeping this span active in the new task.
    ///
    /// Use this instead of raw `Task.detached` when child work must remain linked
    /// to the current Terra trace even after crossing a detached-task boundary.
    public func detached<R: Sendable>(
      priority: TaskPriority? = nil,
      _ body: @escaping @Sendable (SpanHandle) async throws -> R
    ) -> Task<R, Error> {
      let inheritedAgentContext = Terra.agentContext
      return Task.detached(priority: priority) {
        guard !isEnded else {
          NSLog("Detached work launched from an ended Terra span; continuing without parent linkage.")
          return try await Terra.$agentContext.withValue(inheritedAgentContext) {
            try await Terra._withDetachedParentEndedMarker {
              try await body(self)
            }
          }
        }
        return try await Terra.$agentContext.withValue(inheritedAgentContext) {
          try await Terra._withActiveSpan(self) {
            try await body(self)
          }
        }
      }
    }

    @discardableResult
    public func infer<R: Sendable>(
      _ model: String,
      prompt: String? = nil,
      provider: ProviderID? = nil,
      runtime: RuntimeID? = nil,
      temperature: Double? = nil,
      maxTokens: Int? = nil,
      _ body: @escaping @Sendable () async throws -> R
    ) async rethrows -> R {
      try await infer(
        model,
        prompt: prompt,
        provider: provider,
        runtime: runtime,
        temperature: temperature,
        maxTokens: maxTokens
      ) { _ in
        try await body()
      }
    }

    @discardableResult
    public func infer<R: Sendable>(
      _ model: String,
      prompt: String? = nil,
      provider: ProviderID? = nil,
      runtime: RuntimeID? = nil,
      temperature: Double? = nil,
      maxTokens: Int? = nil,
      _ body: @escaping @Sendable (SpanHandle) async throws -> R
    ) async rethrows -> R {
      try await Terra
        .infer(
          model,
          prompt: prompt,
          provider: provider,
          runtime: runtime,
          temperature: temperature,
          maxTokens: maxTokens
        )
        .under(self)
        .run(body)
    }

    @discardableResult
    public func infer<R: Sendable>(
      _ model: String,
      messages: [ChatMessage],
      prompt: String? = nil,
      provider: ProviderID? = nil,
      runtime: RuntimeID? = nil,
      temperature: Double? = nil,
      maxTokens: Int? = nil,
      _ body: @escaping @Sendable () async throws -> R
    ) async rethrows -> R {
      try await infer(
        model,
        messages: messages,
        prompt: prompt,
        provider: provider,
        runtime: runtime,
        temperature: temperature,
        maxTokens: maxTokens
      ) { _ in
        try await body()
      }
    }

    @discardableResult
    public func infer<R: Sendable>(
      _ model: String,
      messages: [ChatMessage],
      prompt: String? = nil,
      provider: ProviderID? = nil,
      runtime: RuntimeID? = nil,
      temperature: Double? = nil,
      maxTokens: Int? = nil,
      _ body: @escaping @Sendable (SpanHandle) async throws -> R
    ) async rethrows -> R {
      try await Terra
        .infer(
          model,
          messages: messages,
          prompt: prompt,
          provider: provider,
          runtime: runtime,
          temperature: temperature,
          maxTokens: maxTokens
        )
        .under(self)
        .run(body)
    }

    @discardableResult
    public func stream<R: Sendable>(
      _ model: String,
      prompt: String? = nil,
      provider: ProviderID? = nil,
      runtime: RuntimeID? = nil,
      temperature: Double? = nil,
      maxTokens: Int? = nil,
      expectedTokens: Int? = nil,
      _ body: @escaping @Sendable () async throws -> R
    ) async rethrows -> R {
      try await stream(
        model,
        prompt: prompt,
        provider: provider,
        runtime: runtime,
        temperature: temperature,
        maxTokens: maxTokens,
        expectedTokens: expectedTokens
      ) { _ in
        try await body()
      }
    }

    @discardableResult
    public func stream<R: Sendable>(
      _ model: String,
      prompt: String? = nil,
      provider: ProviderID? = nil,
      runtime: RuntimeID? = nil,
      temperature: Double? = nil,
      maxTokens: Int? = nil,
      expectedTokens: Int? = nil,
      _ body: @escaping @Sendable (SpanHandle) async throws -> R
    ) async rethrows -> R {
      try await Terra
        .stream(
          model,
          prompt: prompt,
          provider: provider,
          runtime: runtime,
          temperature: temperature,
          maxTokens: maxTokens,
          expectedTokens: expectedTokens
        )
        .under(self)
        .run(body)
    }

    @discardableResult
    public func tool<R: Sendable>(
      _ name: String,
      callId: String? = nil,
      type: String? = nil,
      provider: ProviderID? = nil,
      runtime: RuntimeID? = nil,
      _ body: @escaping @Sendable () async throws -> R
    ) async rethrows -> R {
      try await tool(
        name,
        callId: callId,
        type: type,
        provider: provider,
        runtime: runtime
      ) { _ in
        try await body()
      }
    }

    @discardableResult
    public func tool<R: Sendable>(
      _ name: String,
      callId: String? = nil,
      type: String? = nil,
      provider: ProviderID? = nil,
      runtime: RuntimeID? = nil,
      _ body: @escaping @Sendable (SpanHandle) async throws -> R
    ) async rethrows -> R {
      let operation = if let callId {
        Terra.tool(name, callId: callId, type: type, provider: provider, runtime: runtime)
      } else {
        Terra.tool(name, type: type, provider: provider, runtime: runtime)
      }

      return try await operation
        .under(self)
        .run(body)
    }

    @discardableResult
    public func embed<R: Sendable>(
      _ model: String,
      inputCount: Int? = nil,
      provider: ProviderID? = nil,
      runtime: RuntimeID? = nil,
      _ body: @escaping @Sendable () async throws -> R
    ) async rethrows -> R {
      try await embed(model, inputCount: inputCount, provider: provider, runtime: runtime) { _ in
        try await body()
      }
    }

    @discardableResult
    public func embed<R: Sendable>(
      _ model: String,
      inputCount: Int? = nil,
      provider: ProviderID? = nil,
      runtime: RuntimeID? = nil,
      _ body: @escaping @Sendable (SpanHandle) async throws -> R
    ) async rethrows -> R {
      try await Terra
        .embed(model, inputCount: inputCount, provider: provider, runtime: runtime)
        .under(self)
        .run(body)
    }

    @discardableResult
    public func safety<R: Sendable>(
      _ name: String,
      subject: String? = nil,
      provider: ProviderID? = nil,
      runtime: RuntimeID? = nil,
      _ body: @escaping @Sendable () async throws -> R
    ) async rethrows -> R {
      try await safety(name, subject: subject, provider: provider, runtime: runtime) { _ in
        try await body()
      }
    }

    @discardableResult
    public func safety<R: Sendable>(
      _ name: String,
      subject: String? = nil,
      provider: ProviderID? = nil,
      runtime: RuntimeID? = nil,
      _ body: @escaping @Sendable (SpanHandle) async throws -> R
    ) async rethrows -> R {
      try await Terra
        .safety(name, subject: subject, provider: provider, runtime: runtime)
        .under(self)
        .run(body)
    }

    @discardableResult
    public func agent<R: Sendable>(
      _ name: String,
      id: String? = nil,
      provider: ProviderID? = nil,
      runtime: RuntimeID? = nil,
      _ body: @escaping @Sendable () async throws -> R
    ) async rethrows -> R {
      try await agent(name, id: id, provider: provider, runtime: runtime) { _ in
        try await body()
      }
    }

    @discardableResult
    public func agent<R: Sendable>(
      _ name: String,
      id: String? = nil,
      provider: ProviderID? = nil,
      runtime: RuntimeID? = nil,
      _ body: @escaping @Sendable (SpanHandle) async throws -> R
    ) async rethrows -> R {
      try await Terra
        .agent(name, id: id, provider: provider, runtime: runtime)
        .under(self)
        .run(body)
    }

    package func installStreamingCallbacks(
      onChunk: @escaping @Sendable (Int) -> Void,
      onOutputTokens: @escaping @Sendable (Int) -> Void,
      onFirstToken: @escaping @Sendable () -> Void
    ) {
      storage.installStreamingCallbacks(
        onChunk: onChunk,
        onOutputTokens: onOutputTokens,
        onFirstToken: onFirstToken
      )
    }
  }

  fileprivate enum _SpanMutationValue {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
  }

  private final class _SpanRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var handles: [String: _SpanHandleStorage] = [:]

    func set(_ storage: _SpanHandleStorage) {
      lock.lock()
      handles[storage.spanId] = storage
      lock.unlock()
    }

    func get(spanId: String) -> _SpanHandleStorage? {
      lock.lock()
      let storage = handles[spanId]
      lock.unlock()
      return storage
    }

    func remove(spanId: String) {
      lock.lock()
      handles.removeValue(forKey: spanId)
      lock.unlock()
    }

    func snapshot() -> [_SpanHandleStorage] {
      lock.lock()
      let values = Array(handles.values)
      lock.unlock()
      return values
    }
  }

  private static let spanRegistry = _SpanRegistry()
  private static let spanSequenceLock = NSLock()
  private static var spanSequence = 0

  private static func nextSpanSequence() -> Int {
    spanSequenceLock.lock()
    defer { spanSequenceLock.unlock() }
    defer { spanSequence += 1 }
    return spanSequence
  }

  private final class _TaskSpanRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var stacks: [Int: [String]] = [:]

    func push(spanId: String, taskKey: Int?) {
      guard let taskKey else { return }
      lock.lock()
      stacks[taskKey, default: []].append(spanId)
      lock.unlock()
    }

    func pop(spanId: String, taskKey: Int?) {
      guard let taskKey else { return }
      lock.lock()
      guard var stack = stacks[taskKey] else {
        lock.unlock()
        return
      }
      if let index = stack.lastIndex(of: spanId) {
        stack.remove(at: index)
      }
      if stack.isEmpty {
        stacks.removeValue(forKey: taskKey)
      } else {
        stacks[taskKey] = stack
      }
      lock.unlock()
    }

    func currentSpanId(taskKey: Int?) -> String? {
      guard let taskKey else { return nil }
      lock.lock()
      let spanId = stacks[taskKey]?.last
      lock.unlock()
      return spanId
    }
  }

  private static let taskSpanRegistry = _TaskSpanRegistry()

  private final class _HookRegistry: @unchecked Sendable {
    typealias StartHook = @Sendable (SpanHandle) -> Void
    typealias EndHook = @Sendable (SpanHandle, Duration) -> Void
    typealias ErrorHook = @Sendable (any Error, SpanHandle) -> Void

    private let lock = NSLock()
    private var startHooks: [StartHook] = []
    private var endHooks: [EndHook] = []
    private var errorHooks: [ErrorHook] = []

    func addStart(_ hook: @escaping StartHook) {
      lock.lock()
      startHooks.append(hook)
      lock.unlock()
    }

    func addEnd(_ hook: @escaping EndHook) {
      lock.lock()
      endHooks.append(hook)
      lock.unlock()
    }

    func addError(_ hook: @escaping ErrorHook) {
      lock.lock()
      errorHooks.append(hook)
      lock.unlock()
    }

    func removeAll() {
      lock.lock()
      startHooks.removeAll()
      endHooks.removeAll()
      errorHooks.removeAll()
      lock.unlock()
    }

    func snapshot() -> (start: [StartHook], end: [EndHook], error: [ErrorHook]) {
      lock.lock()
      let snapshot = (startHooks, endHooks, errorHooks)
      lock.unlock()
      return snapshot
    }
  }

  private static let hookRegistry = _HookRegistry()

  fileprivate actor _LoopMessageBuffer {
    private var messages: [ChatMessage]

    init(messages: [ChatMessage]) {
      self.messages = messages
    }

    func snapshot() -> [ChatMessage] {
      messages
    }

    func replace(with newMessages: [ChatMessage]) {
      messages = newMessages
    }

    func append(_ message: ChatMessage) {
      messages.append(message)
    }

    func append(contentsOf newMessages: [ChatMessage]) {
      messages.append(contentsOf: newMessages)
    }

    func clear() {
      messages.removeAll()
    }
  }

  fileprivate final class _SpanHandleStorage: @unchecked Sendable {
    let name: String
    let id: String?
    let traceId: String
    let spanId: String
    let parentId: String?
    let createdOrder: Int
    let startedAt: ContinuousClock.Instant

    fileprivate let span: any Span
    private let ownsLifecycle: Bool
    private let registryKey: String?
    fileprivate let ownerTaskKey: Int?
    private let guidance: String
    private let onEvent: (@Sendable (String) -> Void)?
    private let onAttribute: (@Sendable (String, TraceScalar) -> Void)?
    private let onError: (@Sendable (any Error) -> Void)?
    private let onTokens: (@Sendable (Int?, Int?) -> Void)?
    private let onResponseModel: (@Sendable (String) -> Void)?
    private let lock = NSLock()
    private var ended = false
    private var attributes: [String: AttributeValue]
    private var onChunk: (@Sendable (Int) -> Void)?
    private var onOutputTokens: (@Sendable (Int) -> Void)?
    private var onFirstToken: (@Sendable () -> Void)?

    init(
      name: String,
      id: String?,
      span: any Span,
      parentSpan: (any Span)?,
      initialAttributes: [String: AttributeValue],
      ownsLifecycle: Bool,
      registryKey: String?,
      ownerTaskKey: Int?,
      guidance: String,
      onEvent: (@Sendable (String) -> Void)? = nil,
      onAttribute: (@Sendable (String, TraceScalar) -> Void)? = nil,
      onError: (@Sendable (any Error) -> Void)? = nil,
      onTokens: (@Sendable (Int?, Int?) -> Void)? = nil,
      onResponseModel: (@Sendable (String) -> Void)? = nil,
      onChunk: (@Sendable (Int) -> Void)? = nil,
      onOutputTokens: (@Sendable (Int) -> Void)? = nil,
      onFirstToken: (@Sendable () -> Void)? = nil
    ) {
      self.name = name
      self.id = id
      self.traceId = span.context.traceId.hexString
      self.spanId = span.context.spanId.hexString
      self.parentId = parentSpan?.context.spanId.hexString
      self.createdOrder = Terra.nextSpanSequence()
      self.startedAt = ContinuousClock.now
      self.span = span
      self.ownsLifecycle = ownsLifecycle
      self.registryKey = registryKey
      self.ownerTaskKey = ownerTaskKey
      self.guidance = guidance
      self.onEvent = onEvent
      self.onAttribute = onAttribute
      self.onError = onError
      self.onTokens = onTokens
      self.onResponseModel = onResponseModel
      self.attributes = initialAttributes
      self.onChunk = onChunk
      self.onOutputTokens = onOutputTokens
      self.onFirstToken = onFirstToken
    }

    var isEnded: Bool {
      lock.lock()
      let value = ended
      lock.unlock()
      return value
    }

    func event(_ name: String) {
      guard validateMutation() else { return }
      span.addEvent(name: name)
      onEvent?(name)
    }

    func attribute(_ key: String, _ value: _SpanMutationValue) {
      guard validateMutation() else { return }
      let telemetryValue: AttributeValue
      switch value {
      case .string(let value):
        telemetryValue = .string(value)
      case .int(let value):
        telemetryValue = .int(value)
      case .double(let value):
        telemetryValue = .double(value)
      case .bool(let value):
        telemetryValue = .bool(value)
      }
      lock.lock()
      attributes[key] = telemetryValue
      lock.unlock()
      span.setAttribute(key: key, value: telemetryValue)
      let scalar: TraceScalar
      switch value {
      case .string(let value): scalar = .string(value)
      case .int(let value): scalar = .int(value)
      case .double(let value): scalar = .double(value)
      case .bool(let value): scalar = .bool(value)
      }
      onAttribute?(key, scalar)
    }

    func recordError(_ error: any Error) {
      guard validateMutation() else { return }
      let message = String(describing: error)
      let exceptionType = String(reflecting: type(of: error))
      let shouldCaptureMessage = Runtime.shared.privacy.shouldCapture(includeContent: false)

      span.status = .error(description: shouldCaptureMessage ? message : exceptionType)

      var attributes: [String: AttributeValue] = [
        "exception.type": .string(exceptionType),
      ]
      if shouldCaptureMessage {
        attributes["exception.message"] = .string(message)
      }

      span.addEvent(name: "exception", attributes: attributes, timestamp: Date())
      onError?(error)
      Terra._emitErrorHook(error, span: SpanHandle(storage: self))
    }

    func tokens(input: Int?, output: Int?) {
      guard validateMutation() else { return }
      if let input {
        attribute(Keys.GenAI.usageInputTokens, .int(input))
      }
      if let output {
        attribute(Keys.GenAI.usageOutputTokens, .int(output))
      }
      onTokens?(input, output)
    }

    func responseModel(_ value: String) {
      guard validateMutation() else { return }
      attribute(Keys.GenAI.responseModel, .string(value))
      onResponseModel?(value)
    }

    func installStreamingCallbacks(
      onChunk: @escaping @Sendable (Int) -> Void,
      onOutputTokens: @escaping @Sendable (Int) -> Void,
      onFirstToken: @escaping @Sendable () -> Void
    ) {
      lock.lock()
      self.onChunk = onChunk
      self.onOutputTokens = onOutputTokens
      self.onFirstToken = onFirstToken
      lock.unlock()
    }

    func chunk(_ tokens: Int) {
      guard validateMutation() else { return }
      lock.lock()
      let handler = onChunk
      lock.unlock()
      guard let handler else {
        emitStreamingGuidance()
        return
      }
      handler(tokens)
    }

    func outputTokens(_ total: Int) {
      guard validateMutation() else { return }
      lock.lock()
      let handler = onOutputTokens
      lock.unlock()
      guard let handler else {
        emitStreamingGuidance()
        return
      }
      handler(total)
    }

    func firstToken() {
      guard validateMutation() else { return }
      lock.lock()
      let handler = onFirstToken
      lock.unlock()
      guard let handler else {
        emitStreamingGuidance()
        return
      }
      handler()
    }

    func attributeValue(for key: String) -> AttributeValue? {
      lock.lock()
      let value = attributes[key]
      lock.unlock()
      return value
    }

    func end() {
      lock.lock()
      if ended {
        lock.unlock()
        emitGuidance()
        return
      }
      guard ownsLifecycle else {
        lock.unlock()
        emitGuidance()
        return
      }
      ended = true
      lock.unlock()

      Terra._emitSpanEndHook(
        span: SpanHandle(storage: self),
        duration: ContinuousClock.now - startedAt
      )
      span.end()
      if let registryKey {
        Terra.taskSpanRegistry.pop(spanId: registryKey, taskKey: ownerTaskKey)
        Terra.spanRegistry.remove(spanId: registryKey)
      }
    }

    private func validateMutation() -> Bool {
      lock.lock()
      let isValid = !ended && span.isRecording
      lock.unlock()
      if !isValid {
        emitGuidance()
      }
      return isValid
    }

    private func emitGuidance() {
      assertionFailure(guidance)
    }

    private func emitStreamingGuidance() {
      assertionFailure(
        "Streaming token helpers are only valid on spans created by Terra.stream(...).run { ... } or SpanHandle.stream(...)."
      )
    }

    func markEndedForAutoLifecycle() -> Bool {
      lock.lock()
      defer { lock.unlock() }
      guard !ended else { return false }
      ended = true
      return true
    }
  }

  package static func _registerActiveSpan(
    name: String,
    id: String? = nil,
    span: any Span,
    parentSpan: (any Span)?,
    initialAttributes: [String: AttributeValue] = [:],
    ownsLifecycle: Bool
  ) -> SpanHandle {
    let registryKey = span.context.spanId.hexString
    let ownerTaskKey = currentTaskKey()
    let storage = _SpanHandleStorage(
      name: name,
      id: id,
      span: span,
      parentSpan: parentSpan,
      initialAttributes: initialAttributes,
      ownsLifecycle: ownsLifecycle,
      registryKey: registryKey,
      ownerTaskKey: ownerTaskKey,
      guidance: """
      For workflows where spans must outlive closures, use Terra.startSpan() or Terra.workflow(...) instead of mutating an ended or externally owned span handle.
      """
    )
    spanRegistry.set(storage)
    taskSpanRegistry.push(spanId: registryKey, taskKey: ownerTaskKey)
    let handle = SpanHandle(storage: storage)
    _emitSpanStartHook(handle)
    return handle
  }

  package static func _unregisterActiveSpan(_ span: any Span) {
    if let storage = spanRegistry.get(spanId: span.context.spanId.hexString) {
      if storage.markEndedForAutoLifecycle() {
        _emitSpanEndHook(
          span: SpanHandle(storage: storage),
          duration: ContinuousClock.now - storage.startedAt
        )
      }
      taskSpanRegistry.pop(spanId: storage.spanId, taskKey: storage.ownerTaskKey)
    }
    spanRegistry.remove(spanId: span.context.spanId.hexString)
  }

  package static func _currentTaskSpan() -> SpanHandle? {
    guard let spanId = taskSpanRegistry.currentSpanId(taskKey: currentTaskKey()) else { return nil }
    guard let storage = spanRegistry.get(spanId: spanId) else { return nil }
    return SpanHandle(storage: storage)
  }

  private static func currentTaskKey() -> Int? {
    withUnsafeCurrentTask { task in
      task?.hashValue
    }
  }

  package static func _hasSwiftTaskContext() -> Bool {
    currentTaskKey() != nil
  }

  package static func _withActiveSpan<R: Sendable>(
    _ span: SpanHandle,
    _ body: @escaping @Sendable () async throws -> R
  ) async throws -> R {
    try await _SpanContext.$current.withValue(span) {
      try await OpenTelemetry.instance.contextProvider.withActiveSpan(span.otelSpan) {
        try await body()
      }
    }
  }

  package static func _withDetachedParentEndedMarker<R: Sendable>(
    _ body: @escaping @Sendable () async throws -> R
  ) async rethrows -> R {
    try await _DetachedParentEndedContext.$current.withValue(true) {
      try await body()
    }
  }

  package static var _hasDetachedParentEndedMarker: Bool {
    _DetachedParentEndedContext.current
  }

  package static func _consumeDetachedParentEndedMarker<R: Sendable>(
    _ body: @escaping @Sendable (Bool) async throws -> R
  ) async rethrows -> R {
    let isSet = _DetachedParentEndedContext.current
    return try await _DetachedParentEndedContext.$current.withValue(false) {
      try await body(isSet)
    }
  }

  package static func _activeSpanSnapshot() -> [SpanHandle] {
    spanRegistry
      .snapshot()
      .sorted { lhs, rhs in
        if lhs.createdOrder == rhs.createdOrder {
          return lhs.spanId < rhs.spanId
        }
        return lhs.createdOrder < rhs.createdOrder
      }
      .map(SpanHandle.init(storage:))
  }

  package static func _emitSpanStartHook(_ span: SpanHandle) {
    for hook in hookRegistry.snapshot().start {
      hook(span)
    }
  }

  package static func _emitSpanEndHook(span: SpanHandle, duration: Duration) {
    for hook in hookRegistry.snapshot().end {
      hook(span, duration)
    }
  }

  package static func _emitErrorHook(_ error: any Error, span: SpanHandle) {
    for hook in hookRegistry.snapshot().error {
      hook(error, span)
    }
  }

  /// Returns the currently active Terra span, if one is registered in the current context.
  ///
  /// Use this for debugging propagation and for linking child work to the active
  /// trace without dropping into OpenTelemetry APIs.
  ///
  /// ```swift
  /// let result = try await Terra.workflow(name: "work") { _ in
  ///   if let current = Terra.currentSpan() {
  ///     print(current.parentId ?? "root")
  ///   }
  ///   return "ok"
  /// }
  /// ```
  public static func currentSpan() -> SpanHandle? {
    if let current = _SpanContext.current {
      return current
    }
    if let current = _currentTaskSpan() {
      return current
    }
    guard let active = OpenTelemetry.instance.contextProvider.activeSpan else { return nil }
    if let storage = spanRegistry.get(spanId: active.context.spanId.hexString) {
      return SpanHandle(storage: storage)
    }
    let storage = _SpanHandleStorage(
      name: active.name,
      id: nil,
      span: active,
      parentSpan: nil,
      initialAttributes: [:],
      ownsLifecycle: false,
      registryKey: nil,
      ownerTaskKey: nil,
      guidance: """
      Terra.currentSpan() returned a span owned outside Terra. Use Terra.workflow {} or Terra.startSpan() when you need Terra-managed lifecycle control.
      """
    )
    return SpanHandle(storage: storage)
  }

  /// Returns `true` when the current async context is inside a Terra span.
  ///
  /// ```swift
  /// let value = try await Terra.workflow(name: "check") { _ in
  ///   precondition(Terra.isTracing())
  ///   return "ok"
  /// }
  /// ```
  public static func isTracing() -> Bool {
    currentSpan() != nil
  }

  /// Starts a Terra span with explicit lifecycle control.
  ///
  /// Use this when an agentic workflow needs a parent span that survives beyond a
  /// single `.run {}` closure, such as deferred tool execution or multi-phase work.
  ///
  /// ```swift
  /// let span = Terra.startSpan(name: "tool-call", id: "call-42")
  /// span.event("queued")
  /// span.end()
  /// ```
  public static func startSpan(
    name: String,
    id: String? = nil,
    attributes: [String: AttributeValue] = [:]
  ) -> SpanHandle {
    let parentSpan =
      _SpanContext.current.flatMap { $0.isEnded ? nil : $0.otelSpan }
      ?? _currentTaskSpan().flatMap { $0.isEnded ? nil : $0.otelSpan }
      ?? OpenTelemetry.instance.contextProvider.activeSpan
    let spanBuilder = tracer().spanBuilder(spanName: name).setSpanKind(spanKind: .internal)
    if let parentSpan {
      spanBuilder.setParent(parentSpan)
    }
    for (key, value) in attributes {
      spanBuilder.setAttribute(key: key, value: value)
    }
    if let id {
      spanBuilder.setAttribute(key: "terra.trace.id", value: .string(id))
    }
    let span = spanBuilder.startSpan()
    if _DetachedParentEndedContext.current {
      span.addEvent(name: "detached.parent.ended")
    }
    return _registerActiveSpan(
      name: name,
      id: id,
      span: span,
      parentSpan: parentSpan,
      initialAttributes: attributes,
      ownsLifecycle: true
    )
  }

  /// Traces a workflow under one root span and exposes `SpanHandle` as the only public tracing handle.
  public static func workflow<R: Sendable>(
    name: String,
    id: String? = nil,
    _ body: @escaping @Sendable (SpanHandle) async throws -> R
  ) async throws -> R {
    try await _runWorkflowRoot(name: name, id: id) { span, _ in
      try await body(span)
    }
  }

  /// Traces a workflow with a buffered transcript helper that writes back on success and failure.
  public static func workflow<R: Sendable>(
    name: String,
    id: String? = nil,
    messages: inout [ChatMessage],
    _ body: @escaping @Sendable (SpanHandle, WorkflowTranscript) async throws -> R
  ) async throws -> R {
    let buffer = _LoopMessageBuffer(messages: messages)
    let transcript = WorkflowTranscript(storage: buffer)

    do {
      let result = try await _runWorkflowRoot(name: name, id: id) { span, _ in
        try await body(span, transcript)
      }
      messages = await transcript.snapshot()
      return result
    } catch {
      messages = await transcript.snapshot()
      throw error
    }
  }

  private static func _runWorkflowRoot<R: Sendable>(
    name: String,
    id: String? = nil,
    _ body: @escaping @Sendable (SpanHandle, AgentContext) async throws -> R
  ) async throws -> R {
    var attributes: [String: AttributeValue] = [
      "terra.workflow.name": .string(name),
    ]
    if let id {
      attributes["terra.workflow.id"] = .string(id)
    }

    let span = startSpan(name: name, id: id, attributes: attributes)
    let context = AgentContext()
    return try await Terra.$agentContext.withValue(context) {
      try await _withActiveSpan(span) {
        defer {
          let snapshot = context.snapshot()
          span.attribute("terra.workflow.tools_used", snapshot.toolsUsed.sorted().joined(separator: ","))
          span.attribute("terra.workflow.models_used", snapshot.modelsUsed.sorted().joined(separator: ","))
          span.attribute("terra.workflow.inference_count", snapshot.inferenceCount)
          span.attribute("terra.workflow.tool_call_count", snapshot.toolCallCount)
          span.end()
        }
        return try await body(span, context)
      }
    }
  }

  public struct WorkflowTranscript: Sendable {
    private let storage: _LoopMessageBuffer

    fileprivate init(storage: _LoopMessageBuffer) {
      self.storage = storage
    }

    public func snapshot() async -> [ChatMessage] {
      await storage.snapshot()
    }

    public func replace(with messages: [ChatMessage]) async {
      await storage.replace(with: messages)
    }

    public func append(_ message: ChatMessage) async {
      await storage.append(message)
    }

    public func append(contentsOf messages: [ChatMessage]) async {
      await storage.append(contentsOf: messages)
    }

    public func clear() async {
      await storage.clear()
    }
  }

  package static func _testSpanHandle(
    onEvent: @escaping @Sendable (String) -> Void = { _ in },
    onAttribute: @escaping @Sendable (String, TraceScalar) -> Void = { _, _ in },
    onError: @escaping @Sendable (any Error) -> Void = { _ in },
    onTokens: @escaping @Sendable (Int?, Int?) -> Void = { _, _ in },
    onResponseModel: @escaping @Sendable (String) -> Void = { _ in },
    onChunk: @escaping @Sendable (Int) -> Void = { _ in },
    onOutputTokens: @escaping @Sendable (Int) -> Void = { _ in },
    onFirstToken: @escaping @Sendable () -> Void = {}
  ) -> SpanHandle {
    let span = tracer().spanBuilder(spanName: "terra.test.span").startSpan()
    let storage = _SpanHandleStorage(
      name: "terra.test.span",
      id: nil,
      span: span,
      parentSpan: nil,
      initialAttributes: [:],
      ownsLifecycle: false,
      registryKey: nil,
      ownerTaskKey: nil,
      guidance: "Synthetic test span handle is invalid outside the test seam.",
      onEvent: onEvent,
      onAttribute: onAttribute,
      onError: onError,
      onTokens: onTokens,
      onResponseModel: onResponseModel,
      onChunk: onChunk,
      onOutputTokens: onOutputTokens,
      onFirstToken: onFirstToken
    )
    return SpanHandle(storage: storage)
  }

  package static func _invalidSpanHandle(guidance: String) -> SpanHandle {
    let span = tracer().spanBuilder(spanName: "terra.invalid.span").startSpan()
    span.end()
    let storage = _SpanHandleStorage(
      name: "terra.invalid.span",
      id: nil,
      span: span,
      parentSpan: nil,
      initialAttributes: [:],
      ownsLifecycle: false,
      registryKey: nil,
      ownerTaskKey: nil,
      guidance: guidance
    )
    return SpanHandle(storage: storage)
  }

  /// Returns all Terra spans that are currently active in the process.
  ///
  /// Use this to inspect long-running workflows and background work without
  /// attaching a debugger or reading OpenTelemetry internals.
  ///
  /// ```swift
  /// let spans = Terra.activeSpans()
  /// print(spans.map(\\.name))
  /// ```
  public static func activeSpans() -> [SpanHandle] {
    _activeSpanSnapshot()
  }

  /// Supported output formats for `Terra.visualize`.
  public enum VisualizationFormat: Sendable, Hashable {
    case ascii
    case json
  }

  /// Registers a callback for every Terra span start.
  ///
  /// Use hooks when you want lightweight local behaviors such as logging slow
  /// traces or mirroring active span state into a custom debug UI.
  public static func onSpanStart(_ hook: @escaping @Sendable (SpanHandle) -> Void) {
    hookRegistry.addStart(hook)
  }

  /// Registers a callback for every Terra span end.
  public static func onSpanEnd(_ hook: @escaping @Sendable (SpanHandle, Duration) -> Void) {
    hookRegistry.addEnd(hook)
  }

  /// Registers a callback for every Terra error recorded on an active span.
  public static func onError(_ hook: @escaping @Sendable (any Error, SpanHandle) -> Void) {
    hookRegistry.addError(hook)
  }

  /// Removes all registered span lifecycle hooks.
  public static func removeHooks() {
    hookRegistry.removeAll()
  }

  /// Exports a hierarchy of active spans as ASCII tree output by default.
  ///
  /// The ASCII format is optimized for terminal debugging and for coding agents
  /// that need to understand parent/child relationships from plain text.
  public static func visualize(_ spans: [SpanHandle]) -> String {
    visualize(spans, format: .ascii)
  }

  /// Exports a hierarchy of active spans as ASCII or JSON.
  public static func visualize(_ spans: [SpanHandle], format: VisualizationFormat) -> String {
    let ordered = spans.sorted {
      if $0.parentId == $1.parentId {
        return $0.spanId < $1.spanId
      }
      return ($0.parentId ?? "") < ($1.parentId ?? "")
    }

    let nodes = ordered.map { span in
      _VisualizationNode(
        spanId: span.spanId,
        parentId: span.parentId,
        label: span.id.map { "\(span.name) (\($0))" } ?? span.name
      )
    }

    switch format {
    case .ascii:
      return _renderASCII(nodes)
    case .json:
      return _renderJSON(nodes)
    }
  }

  /// Protocol for services that want a lightweight Terra-managed tracing wrapper.
  ///
  /// Conforming to `TerraInstrumentable` keeps the service interface small and
  /// obvious, while `Terra.register(_:)` adds the standard Terra tracing shape.
  public protocol TerraInstrumentable: Sendable {
    var terraServiceName: String { get }
    func terraExecute(_ input: String) async throws -> String
  }

  /// A traced wrapper around a `TerraInstrumentable` service.
  public struct InstrumentedService<Service: TerraInstrumentable>: TerraInstrumentable, Sendable {
    private let service: Service

    fileprivate init(service: Service) {
      self.service = service
    }

    public var terraServiceName: String {
      service.terraServiceName
    }

    public func terraExecute(_ input: String) async throws -> String {
      try await Terra.workflow(name: "service.\(service.terraServiceName)") { span in
        span
          .attribute(Terra.Keys.Terra.autoInstrumented, true)
          .attribute("terra.service.name", service.terraServiceName)
          .attribute("terra.service.input_length", input.count)
        return try await service.terraExecute(input)
      }
    }
  }

  /// Wraps a service in Terra's standard tracing pattern.
  public static func register<Service: TerraInstrumentable>(_ service: Service) -> InstrumentedService<Service> {
    InstrumentedService(service: service)
  }
}

extension Terra.TerraInstrumentable {
  /// Returns a traced wrapper without requiring callers to remember the Terra factory name.
  public func instrumented() -> Terra.InstrumentedService<Self> {
    Terra.register(self)
  }
}

private extension Terra {
  struct _VisualizationNode: Sendable {
    let spanId: String
    let parentId: String?
    let label: String
  }

  static func _renderASCII(_ nodes: [_VisualizationNode]) -> String {
    guard !nodes.isEmpty else { return "(no active spans)" }

    let children = Dictionary(grouping: nodes, by: \.parentId)
    let roots = (children[nil] ?? []).sorted { $0.label < $1.label }
    var lines: [String] = []

    func visit(_ node: _VisualizationNode, prefix: String, isLast: Bool) {
      let connector = prefix.isEmpty ? "└─ " : (isLast ? "└─ " : "├─ ")
      lines.append(prefix + connector + node.label)
      let nextPrefix = prefix + (prefix.isEmpty ? "   " : (isLast ? "   " : "│  "))
      let descendants = (children[node.spanId] ?? []).sorted { $0.label < $1.label }
      for (index, child) in descendants.enumerated() {
        visit(child, prefix: nextPrefix, isLast: index == descendants.count - 1)
      }
    }

    for (index, root) in roots.enumerated() {
      visit(root, prefix: "", isLast: index == roots.count - 1)
    }

    return lines.joined(separator: "\n")
  }

  static func _renderJSON(_ nodes: [_VisualizationNode]) -> String {
    let payload = nodes.map { node in
      [
        "span_id": node.spanId,
        "parent_id": node.parentId ?? "",
        "label": node.label,
      ]
    }

    guard
      let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
      let string = String(data: data, encoding: .utf8)
    else {
      return "[]"
    }
    return string
  }
}
