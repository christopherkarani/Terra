import Foundation
import OpenTelemetryApi
import TerraSystemProfiler

/// An on-device GenAI observability facade built on OpenTelemetry Swift.
public enum Terra {
  /// The OpenTelemetry instrumentation scope name for Terra spans and metrics.
  public static let instrumentationName: String = "io.opentelemetry.terra"
  public static let instrumentationVersion: String? = nil

  /// Installs Terra configuration. If providers are supplied they may be registered globally.
  public static func install(_ installation: Installation) {
    Runtime.shared.install(installation)
  }

  // MARK: - Public API

  @discardableResult
  public static func withInferenceSpan<R>(
    _ request: InferenceRequest,
    _ body: @Sendable (Scope<InferenceSpan>) async throws -> R
  ) async rethrows -> R {
    let privacy = Runtime.shared.privacy
    let clock = ContinuousClock()
    let started = clock.now

    var attributes: [String: AttributeValue] = [
      Keys.GenAI.operationName: .string(OperationName.inference.rawValue),
      Keys.GenAI.requestModel: .string(request.model),
      Keys.Terra.requestID: .string(request.requestID),
      Keys.Terra.sessionID: .string(Runtime.shared.sessionID),
    ]

    if let runtime = request.runtime {
      attributes[Keys.Terra.runtime] = .string(runtime.rawValue)
      attributes[Keys.Terra.runtimeClass] = .string(runtime.rawValue)
    }
    if let fingerprint = request.modelFingerprint {
      attributes[Keys.Terra.modelFingerprint] = .string(fingerprint.attributeValue)
    }

    if let maxOutputTokens = request.maxOutputTokens {
      attributes[Keys.GenAI.requestMaxTokens] = .int(maxOutputTokens)
    }
    if let temperature = request.temperature {
      attributes[Keys.GenAI.requestTemperature] = .double(temperature)
    }
    if let stream = request.stream {
      attributes[Keys.GenAI.requestStream] = .bool(stream)
    }

    if let prompt = request.prompt, privacy.shouldCapture(promptCapture: request.promptCapture) {
      attributes.merge(
        redactedStringAttributes(
          original: prompt,
          lengthKey: Keys.Terra.promptLength,
          hashKey: Keys.Terra.promptSHA256,
          using: privacy.redaction
        )
      ) { _, new in new }
    }

    return try await withSpan(
      name: SpanNames.inference,
      kind: .internal,
      attributes: attributes
    ) { scope in
      defer {
        let end = clock.now
        let durationMs = monotonicDurationMS(from: started, to: end)
        Runtime.shared.metrics.recordInference(durationMs: durationMs)
        scope.setAttributes([Keys.Terra.latencyEndToEndMs: .double(durationMs)])
      }
      return try await body(scope)
    }
  }

  @discardableResult
  public static func withModelLoadSpan<R>(
    model: String,
    runtime: RuntimeKind,
    requestID: String = UUID().uuidString,
    _ body: @Sendable (Scope<ModelLoadSpan>) async throws -> R
  ) async rethrows -> R {
    let attributes: [String: AttributeValue] = [
      Keys.GenAI.operationName: .string(OperationName.modelLoad.rawValue),
      Keys.GenAI.requestModel: .string(model),
      Keys.Terra.runtime: .string(runtime.rawValue),
      Keys.Terra.runtimeClass: .string(runtime.rawValue),
      Keys.Terra.requestID: .string(requestID),
      Keys.Terra.sessionID: .string(Runtime.shared.sessionID),
      Keys.Terra.stageName: .string(OperationName.modelLoad.rawValue),
    ]

    return try await withSpan(
      name: SpanNames.modelLoad,
      kind: .internal,
      attributes: attributes,
      body
    )
  }

  @discardableResult
  public static func withInferenceStageSpan<R>(
    _ stage: InferenceStage,
    request: InferenceRequest,
    _ body: @Sendable (Scope<InferenceStageSpan>) async throws -> R
  ) async rethrows -> R {
    let spanName: String
    let opName: OperationName
    switch stage {
    case .promptEval:
      spanName = SpanNames.stagePromptEval
      opName = .promptEval
    case .decode:
      spanName = SpanNames.stageDecode
      opName = .decode
    case .streamLifecycle:
      spanName = SpanNames.streamLifecycle
      opName = .streamLifecycle
    }

    var attributes: [String: AttributeValue] = [
      Keys.GenAI.operationName: .string(opName.rawValue),
      Keys.GenAI.requestModel: .string(request.model),
      Keys.Terra.stageName: .string(stage.rawValue),
      Keys.Terra.requestID: .string(request.requestID),
      Keys.Terra.sessionID: .string(Runtime.shared.sessionID),
    ]
    if let runtime = request.runtime {
      attributes[Keys.Terra.runtime] = .string(runtime.rawValue)
      attributes[Keys.Terra.runtimeClass] = .string(runtime.rawValue)
    }

    return try await withSpan(
      name: spanName,
      kind: .internal,
      attributes: attributes,
      body
    )
  }

  @discardableResult
  public static func withStreamingLifecycleSpan<R>(
    _ request: InferenceRequest,
    _ body: @Sendable (Scope<StreamingLifecycleSpan>) async throws -> R
  ) async rethrows -> R {
    var attributes: [String: AttributeValue] = [
      Keys.GenAI.operationName: .string(OperationName.streamLifecycle.rawValue),
      Keys.GenAI.requestModel: .string(request.model),
      Keys.Terra.stageName: .string(InferenceStage.streamLifecycle.rawValue),
      Keys.Terra.requestID: .string(request.requestID),
      Keys.Terra.sessionID: .string(Runtime.shared.sessionID),
    ]
    if let runtime = request.runtime {
      attributes[Keys.Terra.runtime] = .string(runtime.rawValue)
      attributes[Keys.Terra.runtimeClass] = .string(runtime.rawValue)
    }

    return try await withSpan(
      name: SpanNames.streamLifecycle,
      kind: .internal,
      attributes: attributes,
      body
    )
  }

  @discardableResult
  public static func withStreamingInferenceSpan<R>(
    _ request: InferenceRequest,
    _ body: @Sendable (StreamingInferenceScope) async throws -> R
  ) async rethrows -> R {
    var streamingRequest = request
    if streamingRequest.stream == nil {
      streamingRequest.stream = true
    }

    let startedAt = monotonicNow()
    return try await withInferenceSpan(streamingRequest) { scope in
      let streamingScope = StreamingInferenceScope(scope: scope, startedAt: startedAt)
      defer { streamingScope.finish() }
      return try await body(streamingScope)
    }
  }

  @discardableResult
  public static func withAgentInvocationSpan<R>(
    agent: Agent,
    _ body: @Sendable (Scope<AgentInvocationSpan>) async throws -> R
  ) async rethrows -> R {
    var attributes: [String: AttributeValue] = [
      Keys.GenAI.operationName: .string(OperationName.invokeAgent.rawValue),
      Keys.GenAI.agentName: .string(agent.name),
    ]
    if let id = agent.id {
      attributes[Keys.GenAI.agentID] = .string(id)
    }

    return try await withSpan(
      name: SpanNames.agentInvocation,
      kind: .internal,
      attributes: attributes,
      body
    )
  }

  @discardableResult
  public static func withToolExecutionSpan<R>(
    tool: Tool,
    call: ToolCall,
    _ body: @Sendable (Scope<ToolExecutionSpan>) async throws -> R
  ) async rethrows -> R {
    var attributes: [String: AttributeValue] = [
      Keys.GenAI.operationName: .string(OperationName.executeTool.rawValue),
      Keys.GenAI.toolName: .string(tool.name),
      Keys.GenAI.toolCallID: .string(call.id),
    ]
    if let type = tool.type {
      attributes[Keys.GenAI.toolType] = .string(type)
    }

    return try await withSpan(
      name: SpanNames.toolExecution,
      kind: .internal,
      attributes: attributes,
      body
    )
  }

  @discardableResult
  public static func withEmbeddingSpan<R>(
    _ request: EmbeddingRequest,
    _ body: @Sendable (Scope<EmbeddingSpan>) async throws -> R
  ) async rethrows -> R {
    var attributes: [String: AttributeValue] = [
      Keys.GenAI.operationName: .string(OperationName.embeddings.rawValue),
      Keys.GenAI.requestModel: .string(request.model),
    ]
    if let inputCount = request.inputCount {
      attributes[Keys.Terra.embeddingInputCount] = .int(inputCount)
    }

    return try await withSpan(
      name: SpanNames.embedding,
      kind: .internal,
      attributes: attributes,
      body
    )
  }

  @discardableResult
  public static func withSafetyCheckSpan<R>(
    _ check: SafetyCheck,
    _ body: @Sendable (Scope<SafetyCheckSpan>) async throws -> R
  ) async rethrows -> R {
    let privacy = Runtime.shared.privacy

    var attributes: [String: AttributeValue] = [
      Keys.GenAI.operationName: .string(OperationName.safetyCheck.rawValue),
      Keys.Terra.safetyCheckName: .string(check.name),
    ]

    if let subject = check.subject, privacy.shouldCapture(promptCapture: check.subjectCapture) {
      attributes.merge(
        redactedStringAttributes(
          original: subject,
          lengthKey: Keys.Terra.safetySubjectLength,
          hashKey: Keys.Terra.safetySubjectSHA256,
          using: privacy.redaction
        )
      ) { _, new in new }
    }

    return try await withSpan(
      name: SpanNames.safetyCheck,
      kind: .internal,
      attributes: attributes,
      body
    )
  }

  // MARK: - Internal

  private static func withSpan<R, Kind>(
    name: String,
    kind: SpanKind,
    attributes: [String: AttributeValue],
    _ body: @Sendable (Scope<Kind>) async throws -> R
  ) async rethrows -> R {
    let tracer = tracer()
    var mergedAttributes = attributes
    let telemetry = Runtime.shared.telemetry
    mergedAttributes[Keys.Terra.semanticVersion] = .string(telemetry.semanticVersion.rawValue)
    mergedAttributes[Keys.Terra.schemaFamily] = .string(telemetry.schemaFamily)
    mergedAttributes[Keys.Terra.controlLoopMode] = .string(telemetry.controlLoopMode)
    mergedAttributes[Keys.Terra.eventAggregationLevel] = .string(telemetry.eventAggregationLevel)
    mergedAttributes[Keys.Terra.thermalState] = .string(Runtime.thermalStateLabel())
    applyRequiredRootAttributes(to: &mergedAttributes, telemetry: telemetry)

    if let anonymizationKeyID = Runtime.anonymizationKeyID(),
       !anonymizationKeyID.isEmpty {
      mergedAttributes[Keys.Terra.anonymizationKeyID] = .string(anonymizationKeyID)
    }
    let admission = evaluateComplianceAdmission(for: mergedAttributes)
    mergedAttributes = admission.attributes
    if let auditEvent = admission.auditEvent {
      Runtime.shared.appendAudit(auditEvent)
    }

    if admission.shouldSuppressSpan {
      let scope = Scope<Kind>(span: TerraNoOpSpan())
      return try await body(scope)
    }

    let spanBuilder = tracer.spanBuilder(spanName: name)
      .setSpanKind(spanKind: kind)

    for (key, value) in mergedAttributes {
      spanBuilder.setAttribute(key: key, value: value)
    }

    let span = spanBuilder.startSpan()
    let startMemorySnapshot = TerraSystemProfiler.isMemoryProfilerEnabled
      ? TerraSystemProfiler.captureMemorySnapshot()
      : nil

    let scope = Scope<Kind>(span: span)
    defer {
      let endMemorySnapshot = TerraSystemProfiler.isMemoryProfilerEnabled
        ? TerraSystemProfiler.captureMemorySnapshot()
        : nil
      let memoryDelta = TerraSystemProfiler.memoryDeltaAttributes(
        start: startMemorySnapshot,
        end: endMemorySnapshot
      )
      if !memoryDelta.isEmpty {
        scope.setAttributes(memoryDelta)
      }
      span.end()
    }

    return try await OpenTelemetry.instance.contextProvider.withActiveSpan(span) {
      do {
        return try await body(scope)
      } catch let cancellation as CancellationError {
        throw cancellation
      } catch {
        scope.recordError(error)
        throw error
      }
    }
  }

  public final class StreamingInferenceScope: @unchecked Sendable {
    private let scope: Scope<InferenceSpan>
    private let startedAt: ContinuousClock.Instant
    private let clock = ContinuousClock()
    private let lock = NSLock()
    private var firstTokenAt: ContinuousClock.Instant?
    private var previousTokenAt: ContinuousClock.Instant?
    private var outputTokenCount = 0
    private var chunkCount = 0
    private var lifecycleEventCount = 0

    init(scope: Scope<InferenceSpan>, startedAt: ContinuousClock.Instant) {
      self.scope = scope
      self.startedAt = startedAt
    }

    public var span: any Span { scope.span }

    public func addEvent(_ name: String, attributes: [String: AttributeValue] = [:]) {
      scope.addEvent(name, attributes: attributes)
    }

    public func setAttributes(_ attributes: [String: AttributeValue]) {
      scope.setAttributes(attributes)
    }

    public func recordToken(_ count: Int = 1, at timestamp: ContinuousClock.Instant = ContinuousClock().now) {
      guard count > 0 else { return }
      var shouldEmitFirstTokenEvent = false
      lock.lock()
      if firstTokenAt == nil {
        firstTokenAt = timestamp
        shouldEmitFirstTokenEvent = true
      }
      previousTokenAt = timestamp
      outputTokenCount += count
      lock.unlock()

      if shouldEmitFirstTokenEvent {
        scope.addEvent(Keys.Terra.streamFirstTokenEvent)
      }
    }

    public func recordOutputTokenCount(_ totalCount: Int, at timestamp: ContinuousClock.Instant = ContinuousClock().now) {
      guard totalCount >= 0 else { return }
      var shouldEmitFirstTokenEvent = false
      lock.lock()
      if totalCount > 0, firstTokenAt == nil {
        firstTokenAt = timestamp
        shouldEmitFirstTokenEvent = true
      }
      if totalCount > 0 {
        previousTokenAt = timestamp
      }
      outputTokenCount = totalCount
      lock.unlock()

      if shouldEmitFirstTokenEvent {
        scope.addEvent(Keys.Terra.streamFirstTokenEvent)
      }
    }

    public func recordChunk(at timestamp: ContinuousClock.Instant = ContinuousClock().now) {
      var shouldEmitFirstTokenEvent = false
      lock.lock()
      chunkCount += 1
      if firstTokenAt == nil {
        firstTokenAt = timestamp
        shouldEmitFirstTokenEvent = true
      }
      previousTokenAt = timestamp
      lock.unlock()

      if shouldEmitFirstTokenEvent {
        scope.addEvent(Keys.Terra.streamFirstTokenEvent)
      }
    }

    public func recordTokenLifecycle(
      index: Int,
      emittedAt: ContinuousClock.Instant = ContinuousClock().now,
      decodedAt: ContinuousClock.Instant? = nil,
      flushedAt: ContinuousClock.Instant? = nil,
      logProb: Double? = nil
    ) {
      let telemetry = Runtime.shared.telemetry
      guard telemetry.killSwitches.tokenLifecycleEnabled, telemetry.tokenLifecycle.enabled else { return }
      guard index >= 0 else { return }

      lock.lock()
      let shouldSample = index % telemetry.tokenLifecycle.sampleEveryN == 0
      let withinBudget = lifecycleEventCount < telemetry.tokenLifecycle.maxEventsPerSpan
      if shouldSample && withinBudget {
        lifecycleEventCount += 1
      }
      let canRecord = shouldSample && withinBudget
      let previousTokenAt = self.previousTokenAt
      self.previousTokenAt = emittedAt
      if firstTokenAt == nil {
        firstTokenAt = emittedAt
      }
      lock.unlock()

      guard canRecord else { return }

      var attributes: [String: AttributeValue] = [
        Keys.Terra.streamTokenIndex: .int(index),
        Keys.Terra.streamTokenStage: .string("emitted"),
      ]
      if let previousTokenAt {
        attributes[Keys.Terra.streamTokenGapMs] = .double(Terra.monotonicDurationMS(from: previousTokenAt, to: emittedAt))
      }
      if let decodedAt {
        attributes[Keys.Terra.latencyDecodeMs] = .double(Terra.monotonicDurationMS(from: emittedAt, to: decodedAt))
      }
      if let flushedAt {
        attributes[Keys.Terra.latencyEndToEndMs] = .double(Terra.monotonicDurationMS(from: emittedAt, to: flushedAt))
      }
      if let logProb {
        attributes[Keys.Terra.streamTokenLogProb] = .double(logProb)
      }

      scope.addEvent(Keys.Terra.streamLifecycleEvent, attributes: attributes)
    }

    public func recordPromptEval(tokens: Int, durationMs: Double) {
      guard durationMs >= 0 else { return }
      scope.setAttributes([
        Keys.Terra.latencyPromptEvalMs: .double(durationMs),
        Keys.Terra.stageTokenCount: .int(tokens),
      ])
    }

    public func recordDecodeStep(tokenIndex: Int, gapMs: Double) {
      guard tokenIndex >= 0, gapMs >= 0 else { return }
      scope.addEvent(
        SpanNames.stageDecode,
        attributes: [
          Keys.Terra.streamTokenIndex: .int(tokenIndex),
          Keys.Terra.streamTokenGapMs: .double(gapMs),
          Keys.Terra.streamTokenStage: .string("decode"),
        ]
      )
    }

    public func recordStallDetected(gapMs: Double, thresholdMs: Double, baselineP95Ms: Double? = nil) {
      guard gapMs >= 0, thresholdMs > 0 else { return }

      var attributes: [String: AttributeValue] = [
        Keys.Terra.stalledTokenGapMs: .double(gapMs),
        Keys.Terra.stalledTokenThresholdMs: .double(thresholdMs),
      ]
      if let baselineP95Ms {
        attributes[Keys.Terra.stalledTokenBaselineP95Ms] = .double(baselineP95Ms)
      }

      scope.addEvent(Keys.Terra.stalledTokenEvent, attributes: attributes)
      Runtime.shared.metrics.recordAnomaly(kind: "stalled_token")
    }

    func finish(finishedAt: ContinuousClock.Instant = Terra.monotonicNow()) {
      lock.lock()
      let firstTokenAt = self.firstTokenAt
      let outputTokenCount = self.outputTokenCount
      let chunkCount = self.chunkCount
      lock.unlock()

      var attributes: [String: AttributeValue] = [
        Keys.Terra.streamChunkCount: .int(chunkCount),
      ]
      if outputTokenCount > 0 {
        attributes[Keys.Terra.streamOutputTokens] = .int(outputTokenCount)
      }
      if let firstTokenAt {
        let ttftMs = Terra.monotonicDurationMS(from: startedAt, to: firstTokenAt)
        attributes[Keys.Terra.streamTimeToFirstTokenMs] = .double(ttftMs)
        attributes[Keys.Terra.latencyTTFTMs] = .double(ttftMs)
      }
      if outputTokenCount > 0, let firstTokenAt {
        let generationMs = max(Terra.monotonicDurationMS(from: firstTokenAt, to: finishedAt), 0.001)
        attributes[Keys.Terra.streamTokensPerSecond] = .double((Double(outputTokenCount) * 1000) / generationMs)
        attributes[Keys.Terra.latencyDecodeMs] = .double(generationMs)
      }

      scope.setAttributes(attributes)
    }
  }

  private static func tracer() -> any Tracer {
    let tracerProvider = Runtime.shared.tracerProvider ?? OpenTelemetry.instance.tracerProvider

    if let version = instrumentationVersion {
      return tracerProvider.get(instrumentationName: instrumentationName, instrumentationVersion: version)
    }
    return tracerProvider.get(instrumentationName: instrumentationName)
  }

  private static func redactedStringAttributes(
    original: String,
    lengthKey: String,
    hashKey: String,
    using strategy: RedactionStrategy
  ) -> [String: AttributeValue] {
    switch strategy {
    case .drop:
      return [:]
    case .lengthOnly:
      return [lengthKey: .int(original.count)]
    case .hashSHA256:
      var attributes: [String: AttributeValue] = [lengthKey: .int(original.count)]
      if let hash = Runtime.anonymizedHash(of: original, for: hashKey) {
        attributes[hashKey] = .string(hash)
      }
      return attributes
    }
  }

  static func emitRecommendation(_ recommendation: Recommendation, on scope: Scope<InferenceSpan>? = nil) {
    let recommendationID = recommendation.id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      ? recommendation.id!.trimmingCharacters(in: .whitespacesAndNewlines)
      : recommendation.kind.rawValue

    guard Runtime.shared.shouldEmitRecommendation(
      id: recommendationID,
      confidence: recommendation.confidence
    ) else {
      return
    }

    var attributes: [String: AttributeValue] = [
      Keys.Terra.recommendationKind: .string(recommendation.kind.rawValue),
      Keys.Terra.recommendationID: .string(recommendationID),
      Keys.Terra.recommendationConfidence: .double(recommendation.confidence),
      Keys.Terra.recommendationAction: .string(recommendation.action),
      Keys.Terra.recommendationReason: .string(recommendation.reason),
    ]

    for (key, value) in recommendation.attributes {
      attributes["terra.recommendation.meta.\(key)"] = .string(value)
    }

    scope?.addEvent(Keys.Terra.recommendationEvent, attributes: attributes)
    Runtime.shared.metrics.recordRecommendation()
    Runtime.shared.recommendationSink?(recommendation)
  }

  static func monotonicNow() -> ContinuousClock.Instant {
    ContinuousClock().now
  }

  static func monotonicDurationMS(from: ContinuousClock.Instant, to: ContinuousClock.Instant) -> Double {
    let duration = from.duration(to: to)
    return max(duration.milliseconds, 0)
  }

  private static func applyRequiredRootAttributes(
    to attributes: inout [String: AttributeValue],
    telemetry: TelemetryConfiguration
  ) {
    if normalizedStringValue(for: Keys.Terra.requestID, in: attributes) == nil {
      attributes[Keys.Terra.requestID] = .string(UUID().uuidString)
    }

    if normalizedStringValue(for: Keys.Terra.sessionID, in: attributes) == nil {
      attributes[Keys.Terra.sessionID] = .string(Runtime.shared.sessionID)
    }

    let runtimeResolution = resolveRuntime(in: attributes, telemetry: telemetry)
    switch runtimeResolution {
    case .resolved(let runtimeKind, let synthesized):
      attributes[Keys.Terra.runtime] = .string(runtimeKind.rawValue)
      attributes[Keys.Terra.runtimeClass] = .string(runtimeKind.rawValue)
      if synthesized {
        attributes[Keys.Terra.runtimeSynthesis] = .bool(true)
      }
      attributes[Keys.Terra.runtimeConfidence] = .double(synthesized ? 0.5 : 1.0)
    case .unresolved:
      attributes[Keys.Terra.runtimeSynthesis] = .bool(false)
      attributes[Keys.Terra.runtimeConfidence] = .double(0.0)
    }

    if normalizedStringValue(for: Keys.Terra.modelFingerprint, in: attributes) == nil {
      let fallbackRuntime = RuntimeKind.fromContractValue(
        normalizedStringValue(for: Keys.Terra.runtime, in: attributes) ?? ""
      ) ?? telemetry.defaultRuntime
      let defaultModelID = telemetry.defaultFingerprintModelID
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let modelID = defaultModelID.isEmpty ? "unavailable" : defaultModelID
      let fingerprint = ModelFingerprint(modelID: modelID, runtime: fallbackRuntime)
      attributes[Keys.Terra.modelFingerprint] = .string(fingerprint.attributeValue)
      attributes[Keys.Terra.modelFingerprintSynthesis] = .bool(true)
    }
  }

  private static func evaluateComplianceAdmission(
    for attributes: [String: AttributeValue]
  ) -> SpanAdmissionDecision {
    let compliance = Runtime.shared.compliance
    guard compliance.exportControls.enabled else {
      return .allow(attributes)
    }

    guard let runtimeValue = normalizedStringValue(for: Keys.Terra.runtime, in: attributes),
          let runtimeKind = RuntimeKind.fromContractValue(runtimeValue)
    else {
      var annotated = attributes
      annotated[Keys.Terra.policyBlocked] = .bool(true)
      annotated[Keys.Terra.policyReason] = .string("runtime_unresolvable")
      let audit = makePolicyAuditEvent(
        reason: "runtime_unresolvable",
        runtime: normalizedStringValue(for: Keys.Terra.runtime, in: attributes) ?? "unavailable",
        attributes: annotated
      )
      if compliance.exportControls.blockOnViolation {
        return .block(annotated, auditEvent: audit)
      }
      return .annotate(annotated, auditEvent: audit)
    }

    if !compliance.exportControls.allowedRuntimes.contains(runtimeKind) {
      var annotated = attributes
      annotated[Keys.Terra.policyBlocked] = .bool(true)
      annotated[Keys.Terra.policyReason] = .string("runtime_not_allowed")
      let audit = makePolicyAuditEvent(
        reason: "runtime_not_allowed",
        runtime: runtimeKind.rawValue,
        attributes: annotated
      )
      if compliance.exportControls.blockOnViolation {
        return .block(annotated, auditEvent: audit)
      }
      return .annotate(annotated, auditEvent: audit)
    }
    return .allow(attributes)
  }

  private static func makePolicyAuditEvent(
    reason: String,
    runtime: String,
    attributes: [String: AttributeValue]
  ) -> AuditEvent? {
    let compliance = Runtime.shared.compliance
    guard compliance.auditEnabled else { return nil }
    return AuditEvent(
      level: .warning,
      message: "Telemetry span blocked by policy",
      attributes: [
        "reason": reason,
        "runtime": runtime,
        "request_id": normalizedStringValue(for: Keys.Terra.requestID, in: attributes) ?? "unknown",
      ]
    )
  }

  private static func normalizedStringValue(
    for key: String,
    in attributes: [String: AttributeValue]
  ) -> String? {
    guard case .string(let value) = attributes[key] else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private enum RuntimeResolution {
    case resolved(RuntimeKind, synthesized: Bool)
    case unresolved
  }

  private static func resolveRuntime(
    in attributes: [String: AttributeValue],
    telemetry: TelemetryConfiguration
  ) -> RuntimeResolution {
    if let runtime = normalizedStringValue(for: Keys.Terra.runtime, in: attributes),
       let parsed = RuntimeKind.fromContractValue(runtime) {
      return .resolved(parsed, synthesized: false)
    }
    if let runtimeClass = normalizedStringValue(for: Keys.Terra.runtimeClass, in: attributes),
       let parsed = RuntimeKind.fromContractValue(runtimeClass) {
      return .resolved(parsed, synthesized: true)
    }
    if normalizedStringValue(for: Keys.Terra.runtime, in: attributes) == nil,
       normalizedStringValue(for: Keys.Terra.runtimeClass, in: attributes) == nil {
      return .resolved(telemetry.defaultRuntime, synthesized: true)
    }
    return .unresolved
  }

  private enum SpanAdmissionDecision {
    case allow([String: AttributeValue])
    case annotate([String: AttributeValue], auditEvent: AuditEvent?)
    case block([String: AttributeValue], auditEvent: AuditEvent?)

    var attributes: [String: AttributeValue] {
      switch self {
      case .allow(let attributes), .annotate(let attributes, _), .block(let attributes, _):
        return attributes
      }
    }

    var auditEvent: AuditEvent? {
      switch self {
      case .allow:
        return nil
      case .annotate(_, let auditEvent), .block(_, let auditEvent):
        return auditEvent
      }
    }

    var shouldSuppressSpan: Bool {
      if case .block = self {
        return true
      }
      return false
    }
  }
}

private final class TerraNoOpSpan: Span {
  let kind: SpanKind = .internal
  let context = SpanContext.create(
    traceId: TraceId.invalid,
    spanId: SpanId.invalid,
    traceFlags: TraceFlags(),
    traceState: TraceState()
  )
  var isRecording: Bool { false }
  var status: Status = .unset
  var name: String = "terra.noop"
  var description: String { "TerraNoOpSpan" }

  func setAttribute(key: String, value: AttributeValue?) {}
  func setAttributes(_ attributes: [String: AttributeValue]) {}
  func addEvent(name: String) {}
  func addEvent(name: String, timestamp: Date) {}
  func addEvent(name: String, attributes: [String : AttributeValue]) {}
  func addEvent(name: String, attributes: [String : AttributeValue], timestamp: Date) {}
  func recordException(_ exception: any SpanException) {}
  func recordException(_ exception: any SpanException, timestamp: Date) {}
  func recordException(_ exception: any SpanException, attributes: [String : AttributeValue]) {}
  func recordException(_ exception: any SpanException, attributes: [String : AttributeValue], timestamp: Date) {}
  func end() {}
  func end(time: Date) {}
}

private extension Duration {
  var milliseconds: Double {
    let secondsMs = Double(components.seconds) * 1000
    let attosecondsMs = Double(components.attoseconds) / 1_000_000_000_000_000
    return secondsMs + attosecondsMs
  }
}
