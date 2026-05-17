#if canImport(CTerraBridge)

import CTerraBridge
import Foundation
import OpenTelemetryApi

// MARK: - Context Propagation

/// TaskLocal storage for propagating Zig span context through structured concurrency.
enum TerraZigContext {
  @TaskLocal static var activeSpanContext: terra_span_context_t?
}

final class TerraZigInstanceRef: @unchecked Sendable {
  private let lock = NSLock()
  private var instance: OpaquePointer?

  init(instance: OpaquePointer) {
    self.instance = instance
  }

  func withInstance<R>(_ body: (OpaquePointer) -> R?) -> R? {
    lock.lock()
    defer { lock.unlock() }
    let current = instance
    guard let current else { return nil }
    return body(current)
  }

  func takeForShutdown() -> OpaquePointer? {
    lock.lock()
    defer { lock.unlock() }
    let current = instance
    instance = nil
    return current
  }
}

// MARK: - TerraZigTracerProvider

/// An OTel `TracerProvider` backed by the Zig core `terra_t*` instance.
///
/// Returns `TerraZigTracer` instances that create spans through the Zig C ABI
/// instead of the Swift OTel SDK pipeline.
final class TerraZigTracerProvider: TracerProvider {
  private let instanceRef: TerraZigInstanceRef

  init(instanceRef: TerraZigInstanceRef) {
    self.instanceRef = instanceRef
  }

  func get(
    instrumentationName: String,
    instrumentationVersion: String?,
    schemaUrl: String?,
    attributes: [String: AttributeValue]?
  ) -> any Tracer {
    TerraZigTracer(instanceRef: instanceRef)
  }
}

// MARK: - TerraZigTracer

/// An OTel `Tracer` that creates `TerraZigSpanBuilder` instances.
final class TerraZigTracer: Tracer {
  private let instanceRef: TerraZigInstanceRef

  init(instanceRef: TerraZigInstanceRef) {
    self.instanceRef = instanceRef
  }

  func spanBuilder(spanName: String) -> SpanBuilder {
    TerraZigSpanBuilder(instanceRef: instanceRef, spanName: spanName)
  }
}

// MARK: - TerraZigSpanBuilder

/// Accumulates span configuration and starts a Zig-backed span via the C ABI.
///
/// Maps OTel span names to the appropriate `terra_begin_*_span_ctx()` call.
/// Falls back to inference span for unrecognized span names.
final class TerraZigSpanBuilder: SpanBuilder {
  private let instanceRef: TerraZigInstanceRef
  private let spanName: String
  private var spanKind: SpanKind = .internal
  private var attributes: [String: AttributeValue] = [:]
  private var parentSpan: (any Span)?
  private var parentSpanContext: SpanContext?
  private var noParent = false
  private var startTime: Date?
  private var isActiveOnStart = false
  private var links: [(SpanContext, [String: AttributeValue])] = []

  init(instanceRef: TerraZigInstanceRef, spanName: String) {
    self.instanceRef = instanceRef
    self.spanName = spanName
  }

  @discardableResult
  func setParent(_ parent: any Span) -> Self {
    parentSpan = parent
    noParent = false
    return self
  }

  @discardableResult
  func setParent(_ parent: SpanContext) -> Self {
    parentSpanContext = parent
    noParent = false
    return self
  }

  @discardableResult
  func setNoParent() -> Self {
    noParent = true
    parentSpan = nil
    parentSpanContext = nil
    return self
  }

  @discardableResult
  func addLink(spanContext: SpanContext) -> Self {
    links.append((spanContext, [:]))
    return self
  }

  @discardableResult
  func addLink(spanContext: SpanContext, attributes: [String: AttributeValue]) -> Self {
    links.append((spanContext, attributes))
    return self
  }

  @discardableResult
  func setAttribute(key: String, value: AttributeValue) -> Self {
    attributes[key] = Terra.privacySanitizedAttribute(key: key, value: value)
    return self
  }

  @discardableResult
  func setSpanKind(spanKind: SpanKind) -> Self {
    self.spanKind = spanKind
    return self
  }

  @discardableResult
  func setStartTime(time: Date) -> Self {
    startTime = time
    return self
  }

  @discardableResult
  func setActive(_ active: Bool) -> Self {
    isActiveOnStart = active
    return self
  }

  func withActiveSpan<T>(_ operation: (any SpanBase) throws -> T) rethrows -> T {
    let span = startSpan()
    defer { span.end() }
    guard let zigSpan = span as? TerraZigOTelSpan else {
      return try operation(span)
    }
    return try TerraZigContext.$activeSpanContext.withValue(zigSpan.zigContext) {
      try operation(span)
    }
  }

  @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
  func withActiveSpan<T>(_ operation: (any SpanBase) async throws -> T) async rethrows -> T {
    let span = startSpan()
    defer { span.end() }
    guard let zigSpan = span as? TerraZigOTelSpan else {
      return try await operation(span)
    }
    return try await TerraZigContext.$activeSpanContext.withValue(zigSpan.zigContext) {
      try await operation(span)
    }
  }

  func startSpan() -> any Span {
    let includeContent = resolveIncludeContent()
    let model = resolveModel()

    // Resolve parent context: explicit parent > TaskLocal > no parent
    var parentCtx: terra_span_context_t? = resolveParentContext()

    let zigSpan: OpaquePointer? = instanceRef.withInstance { instance in
      withOptionalPointer(to: &parentCtx) { parentPtr in
        beginSpan(instance: instance, parentCtx: parentPtr, model: model, includeContent: includeContent)
      }
    }

    guard let zigSpan else {
      // Zig failed to create a span — return a no-op span as fallback
      return TerraZigNoOpSpan(name: spanName)
    }

    let span = TerraZigOTelSpan(
      zigSpan: zigSpan,
      instanceRef: instanceRef,
      name: spanName,
      kind: spanKind,
      startTime: startTime ?? Date()
    )

    // Apply accumulated attributes
    for (key, value) in attributes {
      span.setAttribute(key: key, value: value)
    }

    return span
  }

  // MARK: - Private Helpers

  private func resolveIncludeContent() -> Bool {
    if let policy = attributes[Terra.Keys.Terra.contentPolicy] {
      switch policy {
      case .string("always"):
        return true
      default:
        return false
      }
    }
    return false
  }

  private func resolveModel() -> String {
    if let model = attributes[Terra.Keys.GenAI.requestModel] {
      switch model {
      case .string(let s): return s
      default: return "unknown"
      }
    }
    return "unknown"
  }

  private func resolveParentContext() -> terra_span_context_t? {
    if noParent { return nil }

    // Explicit parent span
    if let parentSpan = parentSpan as? TerraZigOTelSpan {
      return parentSpan.zigContext
    }

    // Explicit parent span context
    if let parentSpanContext {
      return terra_span_context_t(
        trace_id_hi: parentSpanContext.traceId.idHi,
        trace_id_lo: parentSpanContext.traceId.idLo,
        span_id: parentSpanContext.spanId.rawValue
      )
    }

    // TaskLocal context
    return TerraZigContext.activeSpanContext
  }

  private func beginSpan(
    instance: OpaquePointer,
    parentCtx: UnsafePointer<terra_span_context_t>?,
    model: String,
    includeContent: Bool
  ) -> OpaquePointer? {
    switch spanName {
    case Terra.SpanNames.inference:
      // Route to streaming span if gen_ai.request.stream attribute is set to true
      if isStreamingRequest() {
        return model.withCString { cModel in
          terra_begin_streaming_span_ctx(instance, parentCtx, cModel, includeContent)
        }
      }
      return model.withCString { cModel in
        terra_begin_inference_span_ctx(instance, parentCtx, cModel, includeContent)
      }
    case Terra.SpanNames.embedding:
      return model.withCString { cModel in
        terra_begin_embedding_span_ctx(instance, parentCtx, cModel, includeContent)
      }
    case Terra.SpanNames.agentInvocation:
      let agentName = resolveAgentName()
      return agentName.withCString { cName in
        terra_begin_agent_span_ctx(instance, parentCtx, cName, includeContent)
      }
    case Terra.SpanNames.toolExecution:
      let toolName = resolveToolName()
      return toolName.withCString { cName in
        terra_begin_tool_span_ctx(instance, parentCtx, cName, includeContent)
      }
    case Terra.SpanNames.safetyCheck:
      let checkName = resolveSafetyCheckName()
      return checkName.withCString { cName in
        terra_begin_safety_span_ctx(instance, parentCtx, cName, includeContent)
      }
    default:
      // Unrecognized span name — fall back to inference
      return model.withCString { cModel in
        terra_begin_inference_span_ctx(instance, parentCtx, cModel, includeContent)
      }
    }
  }

  private func resolveAgentName() -> String {
    if let name = attributes[Terra.Keys.GenAI.agentName] {
      switch name {
      case .string(let s): return s
      default: break
      }
    }
    return "unknown"
  }

  private func resolveToolName() -> String {
    if let name = attributes[Terra.Keys.GenAI.toolName] {
      switch name {
      case .string(let s): return s
      default: break
      }
    }
    return "unknown"
  }

  private func resolveSafetyCheckName() -> String {
    if let name = attributes[Terra.Keys.Terra.safetyCheckName] {
      switch name {
      case .string(let s): return s
      default: break
      }
    }
    return "unknown"
  }

  private func isStreamingRequest() -> Bool {
    if let stream = attributes[Terra.Keys.GenAI.requestStream] {
      switch stream {
      case .bool(let b): return b
      case .string(let s): return s == "true"
      default: break
      }
    }
    return false
  }
}

// MARK: - TerraZigOTelSpan

/// An OTel `Span` backed by a Zig `terra_span_t*`.
///
/// All attribute/event/status mutations delegate to `terra_span_set_*` C functions.
/// The span is ended by calling `terra_span_end`.
final class TerraZigOTelSpan: Span, @unchecked Sendable {
  private let zigSpan: OpaquePointer   // terra_span_t*
  private let instanceRef: TerraZigInstanceRef
  private let lock = NSLock()
  private var ended = false
  private var currentStatus: Status = .unset

  let kind: SpanKind
  private(set) var context: SpanContext
  var isRecording: Bool {
    withLockedState { !ended }
  }
  var status: Status {
    get {
      withLockedState { currentStatus }
    }
    set {
      withRecordingSpan {
        currentStatus = newValue
        applyStatusLocked(newValue)
      }
    }
  }
  var name: String

  /// The raw Zig span context for parent propagation.
  let zigContext: terra_span_context_t

  init(
    zigSpan: OpaquePointer,
    instanceRef: TerraZigInstanceRef,
    name: String,
    kind: SpanKind,
    startTime: Date
  ) {
    self.zigSpan = zigSpan
    self.instanceRef = instanceRef
    self.name = name
    self.kind = kind

    // Extract Zig span context
    let ctx = terra_span_context(zigSpan)
    self.zigContext = ctx

    // Map Zig context to OTel SpanContext
    self.context = SpanContext.create(
      traceId: TraceId(idHi: ctx.trace_id_hi, idLo: ctx.trace_id_lo),
      spanId: SpanId(id: ctx.span_id),
      traceFlags: TraceFlags().settingIsSampled(true),
      traceState: TraceState()
    )
  }

  var description: String {
    "TerraZigOTelSpan(\(name), traceId=\(context.traceId.hexString), spanId=\(context.spanId.hexString))"
  }

  // MARK: - Attributes

  func setAttribute(key: String, value: AttributeValue?) {
    guard let value, let sanitizedValue = Terra.privacySanitizedAttribute(key: key, value: value) else { return }
    withRecordingSpan {
      setAttributeLocked(key: key, value: sanitizedValue)
    }
  }

  private func setAttributeLocked(key: String, value: AttributeValue) {
    switch value {
    case .string(let s):
      key.withCString { cKey in
        s.withCString { cVal in
          terra_span_set_string(zigSpan, cKey, cVal)
        }
      }
    case .int(let i):
      key.withCString { cKey in
        terra_span_set_int(zigSpan, cKey, Int64(i))
      }
    case .double(let d):
      key.withCString { cKey in
        terra_span_set_double(zigSpan, cKey, d)
      }
    case .bool(let b):
      key.withCString { cKey in
        terra_span_set_bool(zigSpan, cKey, b)
      }
    default:
      // Arrays and other complex types: serialize as string
      key.withCString { cKey in
        let desc = String(describing: value)
        desc.withCString { cVal in
          terra_span_set_string(zigSpan, cKey, cVal)
        }
      }
    }
  }

  func setAttributes(_ attributes: [String: AttributeValue]) {
    withRecordingSpan {
      for (key, value) in Terra.privacySanitizedAttributes(attributes) {
        setAttributeLocked(key: key, value: value)
      }
    }
  }

  // MARK: - Events

  func addEvent(name: String) {
    withRecordingSpan {
      name.withCString { cName in
        terra_span_add_event(zigSpan, cName)
      }
    }
  }

  func addEvent(name: String, timestamp: Date) {
    withRecordingSpan {
      let nanos = UInt64(timestamp.timeIntervalSince1970 * 1_000_000_000)
      name.withCString { cName in
        terra_span_add_event_ts(zigSpan, cName, nanos)
      }
    }
  }

  func addEvent(name: String, attributes: [String: AttributeValue]) {
    withRecordingSpan {
      // Zig C ABI does not support event attributes directly;
      // set them as span attributes with event-prefixed keys, then add the event.
      for (key, value) in attributes {
        setAttributeLocked(key: "terra.event.\(name).\(key)", value: value)
      }
      name.withCString { cName in
        terra_span_add_event(zigSpan, cName)
      }
    }
  }

  func addEvent(name: String, attributes: [String: AttributeValue], timestamp: Date) {
    withRecordingSpan {
      for (key, value) in attributes {
        setAttributeLocked(key: "terra.event.\(name).\(key)", value: value)
      }
      let nanos = UInt64(timestamp.timeIntervalSince1970 * 1_000_000_000)
      name.withCString { cName in
        terra_span_add_event_ts(zigSpan, cName, nanos)
      }
    }
  }

  // MARK: - Exceptions

  func recordException(_ exception: SpanException) {
    withRecordingSpan {
      recordExceptionLocked(exception)
    }
  }

  private func recordExceptionLocked(_ exception: SpanException) {
    exception.type.withCString { cType in
      (exception.message ?? "").withCString { cMsg in
        terra_span_record_error(zigSpan, cType, cMsg, true)
      }
    }
  }

  // NOTE: The Zig C ABI (terra_span_record_error) does not accept a custom timestamp.
  // The exception timestamp is always set by the Zig-side clock. This timestamp
  // parameter is accepted for OTel Span protocol conformance but not applied.
  func recordException(_ exception: SpanException, timestamp: Date) {
    recordException(exception)
  }

  func recordException(_ exception: SpanException, attributes: [String: AttributeValue]) {
    withRecordingSpan {
      recordExceptionLocked(exception)
      for (key, value) in attributes {
        setAttributeLocked(key: key, value: value)
      }
    }
  }

  // NOTE: The Zig C ABI (terra_span_record_error) does not accept a custom timestamp.
  // The exception timestamp is always set by the Zig-side clock. This timestamp
  // parameter is accepted for OTel Span protocol conformance but not applied.
  func recordException(_ exception: SpanException, attributes: [String: AttributeValue], timestamp: Date) {
    recordException(exception, attributes: attributes)
  }

  // MARK: - End

  func end() {
    let shouldEnd = withLockedState {
      guard !ended else {
        return false
      }
      ended = true
      return true
    }
    if shouldEnd {
      _ = instanceRef.withInstance { instance in
        terra_span_end(instance, zigSpan)
        return true
      }
    }
  }

  // NOTE: The Zig C ABI (terra_span_end) does not accept a custom end timestamp.
  // The span's end time is always set by the Zig-side clock. This timestamp
  // parameter is accepted for OTel Span protocol conformance but not applied.
  func end(time: Date) {
    end()
  }

  // MARK: - Private

  private func applyStatusLocked(_ status: Status) {
    switch status {
    case .ok:
      terra_span_set_status(zigSpan, UInt8(TERRA_STATUS_OK.rawValue), nil)
    case .unset:
      terra_span_set_status(zigSpan, UInt8(TERRA_STATUS_UNSET.rawValue), nil)
    case .error(let description):
      description.withCString { cDesc in
        terra_span_set_status(zigSpan, UInt8(TERRA_STATUS_ERROR.rawValue), cDesc)
      }
    }
  }

  private func withLockedState<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  private func withRecordingSpan(_ body: () -> Void) {
    lock.lock()
    defer { lock.unlock() }
    guard !ended else { return }
    _ = instanceRef.withInstance { _ in
      body()
      return true
    }
  }
}

// MARK: - TerraZigNoOpSpan

/// A fallback no-op span used when Zig fails to create a span.
final class TerraZigNoOpSpan: Span, @unchecked Sendable {
  let kind: SpanKind = .internal
  let context: SpanContext = .create(
    traceId: .invalid,
    spanId: .invalid,
    traceFlags: TraceFlags(),
    traceState: TraceState()
  )
  let isRecording: Bool = false
  var status: Status = .unset
  var name: String
  var description: String { "TerraZigNoOpSpan(\(name))" }

  init(name: String) { self.name = name }

  func setAttribute(key: String, value: AttributeValue?) {}
  func setAttributes(_ attributes: [String: AttributeValue]) {}
  func addEvent(name: String) {}
  func addEvent(name: String, timestamp: Date) {}
  func addEvent(name: String, attributes: [String: AttributeValue]) {}
  func addEvent(name: String, attributes: [String: AttributeValue], timestamp: Date) {}
  func recordException(_ exception: SpanException) {}
  func recordException(_ exception: SpanException, timestamp: Date) {}
  func recordException(_ exception: SpanException, attributes: [String: AttributeValue]) {}
  func recordException(_ exception: SpanException, attributes: [String: AttributeValue], timestamp: Date) {}
  func end() {}
  func end(time: Date) {}
}

// MARK: - Zig Backend Installation

extension Terra {
  private static let zigBackendLock = NSLock()

  /// Install the Zig core as the active telemetry backend.
  ///
  /// This replaces the Swift OTel pipeline with the Zig-based engine:
  /// 1. Calls `terra_init()` to create the native instance
  /// 2. Registers `TerraZigTracerProvider` as the global OTel tracer provider
  /// 3. Configures service name/version from the provided configuration
  ///
  /// After this call, all `Terra.withInferenceSpan()` etc. will route through
  /// the Zig C ABI instead of the Swift OTel SDK.
  package static func installZigBackend(
    serviceName: String? = nil,
    serviceVersion: String? = nil
  ) -> Bool {
    zigBackendLock.lock()
    defer { zigBackendLock.unlock() }

    if _zigInstance != nil {
      Runtime.shared.markRunning()
      return true
    }

    Runtime.shared.markStarting()
    guard let instance = terra_init(nil) else {
      Runtime.shared.markStopped()
      return false
    }

    let instanceRef = TerraZigInstanceRef(instance: instance)
    _zigInstance = instance
    _zigInstanceRef = instanceRef
    Runtime.shared.markRunning()

    // Configure service metadata
    if let name = serviceName {
      name.withCString { cName in
        let ver = serviceVersion ?? "0.0.0"
        ver.withCString { cVer in
          _ = terra_set_service_info(instance, cName, cVer)
        }
      }
    } else if let version = serviceVersion {
      version.withCString { cVer in
        _ = terra_set_service_info(instance, "unknown", cVer)
      }
    }

    // Register the Zig-backed tracer provider as the global OTel provider
    let zigProvider = TerraZigTracerProvider(instanceRef: instanceRef)
    OpenTelemetry.registerTracerProvider(tracerProvider: zigProvider)

    return true
  }

  package static func shutdownZigBackend() {
    zigBackendLock.lock()
    guard let instanceRef = _zigInstanceRef else {
      zigBackendLock.unlock()
      return
    }
    let instance = instanceRef.takeForShutdown()
    _zigInstance = nil
    _zigInstanceRef = nil
    zigBackendLock.unlock()

    guard let instance else { return }
    Runtime.shared.markShuttingDown()
    _ = terra_shutdown(instance)
    Runtime.shared.markStopped()
  }

  /// The raw Zig instance pointer, if the Zig backend was installed.
  /// Used internally for shutdown and test support.
  package private(set) static var _zigInstance: OpaquePointer? = nil
  private static var _zigInstanceRef: TerraZigInstanceRef?
}

// MARK: - Helpers

/// Calls `body` with a pointer to `value` if non-nil, or `nil` otherwise.
private func withOptionalPointer<T, R>(
  to value: inout T?,
  _ body: (UnsafePointer<T>?) -> R
) -> R {
  if var unwrapped = value {
    return withUnsafePointer(to: &unwrapped) { ptr in
      body(ptr)
    }
  } else {
    return body(nil)
  }
}

#endif  // canImport(CTerraBridge)
