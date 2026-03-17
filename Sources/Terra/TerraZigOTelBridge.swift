#if canImport(CTerraBridge)

import CTerraBridge
import Foundation
import OpenTelemetryApi

// MARK: - Context Propagation

/// TaskLocal storage for propagating Zig span context through structured concurrency.
enum TerraZigContext {
  @TaskLocal static var activeSpanContext: terra_span_context_t?
}

// MARK: - TerraZigTracerProvider

/// An OTel `TracerProvider` backed by the Zig core `terra_t*` instance.
///
/// Returns `TerraZigTracer` instances that create spans through the Zig C ABI
/// instead of the Swift OTel SDK pipeline.
final class TerraZigTracerProvider: TracerProvider {
  private let instance: OpaquePointer  // terra_t*

  init(instance: OpaquePointer) {
    self.instance = instance
  }

  func get(
    instrumentationName: String,
    instrumentationVersion: String?,
    schemaUrl: String?,
    attributes: [String: AttributeValue]?
  ) -> any Tracer {
    TerraZigTracer(instance: instance)
  }
}

// MARK: - TerraZigTracer

/// An OTel `Tracer` that creates `TerraZigSpanBuilder` instances.
final class TerraZigTracer: Tracer {
  private let instance: OpaquePointer  // terra_t*

  init(instance: OpaquePointer) {
    self.instance = instance
  }

  func spanBuilder(spanName: String) -> SpanBuilder {
    TerraZigSpanBuilder(instance: instance, spanName: spanName)
  }
}

// MARK: - TerraZigSpanBuilder

/// Accumulates span configuration and starts a Zig-backed span via the C ABI.
///
/// Maps OTel span names to the appropriate `terra_begin_*_span_ctx()` call.
/// Falls back to inference span for unrecognized span names.
final class TerraZigSpanBuilder: SpanBuilder {
  private let instance: OpaquePointer  // terra_t*
  private let spanName: String
  private var spanKind: SpanKind = .internal
  private var attributes: [String: AttributeValue] = [:]
  private var parentSpan: (any Span)?
  private var parentSpanContext: SpanContext?
  private var noParent = false
  private var startTime: Date?
  private var isActiveOnStart = false
  private var links: [(SpanContext, [String: AttributeValue])] = []

  init(instance: OpaquePointer, spanName: String) {
    self.instance = instance
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
    attributes[key] = value
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
    return try operation(span)
  }

  @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
  func withActiveSpan<T>(_ operation: (any SpanBase) async throws -> T) async rethrows -> T {
    let span = startSpan()
    defer { span.end() }
    return try await operation(span)
  }

  func startSpan() -> any Span {
    let includeContent = resolveIncludeContent()
    let model = resolveModel()

    // Resolve parent context: explicit parent > TaskLocal > no parent
    var parentCtx: terra_span_context_t? = resolveParentContext()

    let zigSpan: OpaquePointer? = withOptionalPointer(to: &parentCtx) { parentPtr in
      beginSpan(parentCtx: parentPtr, model: model, includeContent: includeContent)
    }

    guard let zigSpan else {
      // Zig failed to create a span — return a no-op span as fallback
      return TerraZigNoOpSpan(name: spanName)
    }

    let span = TerraZigOTelSpan(
      zigSpan: zigSpan,
      instance: instance,
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
    parentCtx: UnsafePointer<terra_span_context_t>?,
    model: String,
    includeContent: Bool
  ) -> OpaquePointer? {
    switch spanName {
    case Terra.SpanNames.inference:
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
      // For streaming or any unrecognized span name, fall back to inference
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
}

// MARK: - TerraZigOTelSpan

/// An OTel `Span` backed by a Zig `terra_span_t*`.
///
/// All attribute/event/status mutations delegate to `terra_span_set_*` C functions.
/// The span is ended by calling `terra_span_end`.
final class TerraZigOTelSpan: Span, @unchecked Sendable {
  private let zigSpan: OpaquePointer   // terra_span_t*
  private let instance: OpaquePointer  // terra_t*
  private let lock = NSLock()
  private var ended = false

  let kind: SpanKind
  private(set) var context: SpanContext
  var isRecording: Bool { !ended }
  var status: Status = .unset {
    didSet { applyStatus() }
  }
  var name: String

  /// The raw Zig span context for parent propagation.
  let zigContext: terra_span_context_t

  init(
    zigSpan: OpaquePointer,
    instance: OpaquePointer,
    name: String,
    kind: SpanKind,
    startTime: Date
  ) {
    self.zigSpan = zigSpan
    self.instance = instance
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
    guard !ended, let value else { return }
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
    for (key, value) in attributes {
      setAttribute(key: key, value: value)
    }
  }

  // MARK: - Events

  func addEvent(name: String) {
    guard !ended else { return }
    name.withCString { cName in
      terra_span_add_event(zigSpan, cName)
    }
  }

  func addEvent(name: String, timestamp: Date) {
    guard !ended else { return }
    let nanos = UInt64(timestamp.timeIntervalSince1970 * 1_000_000_000)
    name.withCString { cName in
      terra_span_add_event_ts(zigSpan, cName, nanos)
    }
  }

  func addEvent(name: String, attributes: [String: AttributeValue]) {
    guard !ended else { return }
    // Zig C ABI does not support event attributes directly;
    // set them as span attributes with event-prefixed keys, then add the event.
    for (key, value) in attributes {
      setAttribute(key: "event.\(name).\(key)", value: value)
    }
    name.withCString { cName in
      terra_span_add_event(zigSpan, cName)
    }
  }

  func addEvent(name: String, attributes: [String: AttributeValue], timestamp: Date) {
    guard !ended else { return }
    for (key, value) in attributes {
      setAttribute(key: "event.\(name).\(key)", value: value)
    }
    let nanos = UInt64(timestamp.timeIntervalSince1970 * 1_000_000_000)
    name.withCString { cName in
      terra_span_add_event_ts(zigSpan, cName, nanos)
    }
  }

  // MARK: - Exceptions

  func recordException(_ exception: SpanException) {
    guard !ended else { return }
    exception.type.withCString { cType in
      (exception.message ?? "").withCString { cMsg in
        terra_span_record_error(zigSpan, cType, cMsg, true)
      }
    }
  }

  func recordException(_ exception: SpanException, timestamp: Date) {
    recordException(exception)
  }

  func recordException(_ exception: SpanException, attributes: [String: AttributeValue]) {
    recordException(exception)
    setAttributes(attributes)
  }

  func recordException(_ exception: SpanException, attributes: [String: AttributeValue], timestamp: Date) {
    recordException(exception, attributes: attributes)
  }

  // MARK: - End

  func end() {
    lock.lock()
    guard !ended else {
      lock.unlock()
      return
    }
    ended = true
    lock.unlock()

    terra_span_end(instance, zigSpan)
  }

  func end(time: Date) {
    end()
  }

  // MARK: - Private

  private func applyStatus() {
    guard !ended else { return }
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
