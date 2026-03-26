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
  /// let value = try await Terra.trace(name: "inference", id: "issue-42") { span in
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

    /// Records an error on the span and marks it failed.
    public func recordError(_ error: any Error) {
      storage.recordError(error)
    }

    /// Ends the span if this handle owns the lifecycle.
    ///
    /// `Terra.trace {}` owns lifecycle automatically. `Terra.currentSpan()` may return
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
      Task.detached(priority: priority) {
        guard !isEnded else {
          NSLog("Detached work launched from an ended Terra span; continuing without parent linkage.")
          return try await Terra._withDetachedParentEndedMarker {
            try await body(self)
          }
        }
        return try await Terra._withActiveSpan(self) {
          try await body(self)
        }
      }
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
    private let lock = NSLock()
    private var ended = false
    private var attributes: [String: AttributeValue]

    init(
      name: String,
      id: String?,
      span: any Span,
      parentSpan: (any Span)?,
      initialAttributes: [String: AttributeValue],
      ownsLifecycle: Bool,
      registryKey: String?,
      ownerTaskKey: Int?,
      guidance: String
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
      self.attributes = initialAttributes
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
    }

    func recordError(_ error: any Error) {
      guard validateMutation() else { return }
      span.status = .error(description: String(describing: error))
      span.recordException(error)
      Terra._emitErrorHook(error, span: SpanHandle(storage: self))
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
      For agentic workflows where spans must outlive closures, use Terra.startSpan() or Terra.trace {} instead of mutating an ended or externally owned span handle.
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
  /// let result = try await Terra.trace(name: "work") { _ in
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
      Terra.currentSpan() returned a span owned outside Terra. Use Terra.startSpan() or Terra.trace {} when you need explicit lifecycle control.
      """
    )
    return SpanHandle(storage: storage)
  }

  /// Returns `true` when the current async context is inside a Terra span.
  ///
  /// ```swift
  /// let value = try await Terra.trace(name: "check") { _ in
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

  /// Traces a unit of async work with automatic lifecycle and active-context management.
  ///
  /// This is Terra's default entry point for agentic workflows because it makes the
  /// span owner explicit and keeps all later async work inside the same active context.
  ///
  /// ```swift
  /// let value = try await Terra.trace(name: "inference", id: "issue-42") { span in
  ///   span.event("start")
  ///   return "ok"
  /// }
  /// ```
  public static func trace<R: Sendable>(
    name: String,
    id: String? = nil,
    _ body: @escaping @Sendable (SpanHandle) async throws -> R
  ) async throws -> R {
    let span = startSpan(name: name, id: id)
    defer { span.end() }
    return try await _withActiveSpan(span) {
      try await body(span)
    }
  }

  /// Traces a multi-step agentic workflow under one obvious root span.
  ///
  /// Prefer `agentic` when a coding agent will iterate, call tools, or launch
  /// follow-up work that should stay correlated to one long-lived parent span.
  public static func agentic<R: Sendable>(
    name: String,
    id: String? = nil,
    _ body: @escaping @Sendable (AgentHandle) async throws -> R
  ) async throws -> R {
    var attributes: [String: AttributeValue] = [
      Keys.GenAI.operationName: .string(OperationName.invokeAgent.rawValue),
      Keys.GenAI.agentName: .string(name),
    ]
    if let id {
      attributes[Keys.GenAI.agentID] = .string(id)
    }

    let span = startSpan(name: name, id: id, attributes: attributes)
    let context = AgentContext()
    return try await Terra.$agentContext.withValue(context) {
      try await _withActiveSpan(span) {
        defer {
          let snapshot = context.snapshot()
          span.attribute("terra.agent.tools_used", snapshot.toolsUsed.sorted().joined(separator: ","))
          span.attribute("terra.agent.models_used", snapshot.modelsUsed.sorted().joined(separator: ","))
          span.attribute("terra.agent.inference_count", snapshot.inferenceCount)
          span.attribute("terra.agent.tool_call_count", snapshot.toolCallCount)
          span.end()
        }
        return try await body(AgentHandle(span: span, context: context))
      }
    }
  }

  /// A sendable helper for agent loops that need explicit checkpoints and child operations.
  public struct AgentHandle: Sendable {
    private let span: SpanHandle
    private let context: AgentContext?

    fileprivate init(span: SpanHandle, context: AgentContext? = nil) {
      self.span = span
      self.context = context
    }

    public var traceId: String { span.traceId }
    public var spanId: String { span.spanId }
    public var parentSpan: SpanHandle { span }

    /// Records a named checkpoint event under the root agentic span.
    @discardableResult
    public func checkpoint(_ name: String) -> Self {
      span.event("checkpoint.\(name)")
      return self
    }

    /// Records a named event on the agent root span.
    @discardableResult
    public func event(_ name: String) -> Self {
      span.event(name)
      return self
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
      _ body: @escaping @Sendable (TraceHandle) async throws -> R
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
        .under(span)
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
      _ body: @escaping @Sendable (TraceHandle) async throws -> R
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
        .under(span)
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
      _ body: @escaping @Sendable (TraceHandle) async throws -> R
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
        .under(span)
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
      _ body: @escaping @Sendable (TraceHandle) async throws -> R
    ) async rethrows -> R {
      let operation = if let callId {
        Terra.tool(name, callId: callId, type: type, provider: provider, runtime: runtime)
      } else {
        Terra.tool(name, type: type, provider: provider, runtime: runtime)
      }

      return try await operation
        .under(span)
        .run(body)
    }

    /// Runs detached work while keeping the agent root span active.
    public func detached<R: Sendable>(
      priority: TaskPriority? = nil,
      _ body: @escaping @Sendable (AgentHandle) async throws -> R
    ) -> Task<R, Error> {
      span.detached(priority: priority) { _ in
        if let context {
          return try await Terra.$agentContext.withValue(context) {
            try await body(self)
          }
        }
        return try await body(self)
      }
    }
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

  /// Fluent convenience wrapper over Terra's explicit manual tracing APIs.
  ///
  /// Use this when you want to build a multi-step trace progressively while
  /// still keeping `Terra.trace(name:id:_:)` as the canonical mental model.
  public struct TraceBuilder: Sendable {
    private final class State: @unchecked Sendable {
      private let lock = NSLock()
      private var ended = false
      let root: SpanHandle

      init(root: SpanHandle) {
        self.root = root
      }

      func withActiveRoot<R: Sendable>(
        _ body: @escaping @Sendable (SpanHandle) async throws -> R
      ) async throws -> R {
        let span = try rootSpan()
        return try await Terra._withActiveSpan(span) {
          try await body(span)
        }
      }

      func rootSpan() throws -> SpanHandle {
        lock.lock()
        defer { lock.unlock() }
        guard !ended, !root.isEnded else {
          throw Terra.TerraError.guidance(
            message: "This TraceBuilder has already ended.",
            why: "TraceBuilder reuses a single root span. Once that root span is ended, later operations cannot attach child spans or metadata to it.",
            correctAPI: "Create a new builder with Terra.trace(name:) or use Terra.trace(name:id:_:) for one-shot traced work.",
            example: """
            let builder = Terra.trace(name: "request")
            try await builder
              .span("validation") { }
            builder.end()
            """,
            context: ["builder_state": "ended"]
          )
        }
        return root
      }

      func end() {
        lock.lock()
        let shouldEnd = !ended
        ended = true
        lock.unlock()
        if shouldEnd {
          root.end()
        }
      }
    }

    private let state: State

    fileprivate init(root: SpanHandle) {
      state = State(root: root)
    }

    @discardableResult
    public func attribute(_ key: String, _ value: String) -> Self {
      state.root.attribute(key, value)
      return self
    }

    @discardableResult
    public func event(_ name: String) -> Self {
      state.root.event(name)
      return self
    }

    @discardableResult
    public func span(
      _ name: String,
      _ body: @escaping @Sendable () async throws -> Void
    ) async throws -> Self {
      try await state.withActiveRoot { _ in
        try await Terra.trace(name: name) { _ in
          try await body()
        }
      }
      return self
    }

    public func end() {
      state.end()
    }
  }

  /// Starts a fluent trace builder for progressive multi-step workflows.
  ///
  /// This is additive convenience over the canonical closure-based `trace`
  /// entry point. Prefer it when step-by-step composition reads more clearly.
  public static func trace(name: String) -> TraceBuilder {
    TraceBuilder(root: startSpan(name: name))
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
      try await Terra.trace(name: "service.\(service.terraServiceName)") { span in
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
