import Foundation
import OpenTelemetryApi
import TerraSystemProfiler

/// An on-device GenAI observability façade built on OpenTelemetry Swift.
public enum Terra {
  /// The OpenTelemetry instrumentation scope name for Terra spans and metrics.
  public static let instrumentationName: String = "io.opentelemetry.terra"
  public static let instrumentationVersion: String? = nil

  /// Installs Terra configuration. If providers are supplied they may be registered globally.
  public static func install(_ installation: Installation) {
    Runtime.shared.install(installation)
  }

  // MARK: - Public API (Phase 2)

  @discardableResult
  static func withInferenceSpan<R>(
    _ request: InferenceRequest,
    stream: Bool? = nil,
    _ body: @Sendable (Scope<InferenceSpan>) async throws -> R
  ) async rethrows -> R {
    let privacy = Runtime.shared.privacy
    let startInstant = ContinuousClock.now

    var attributes: [String: AttributeValue] = [
      Keys.GenAI.operationName: .string(OperationName.inference.rawValue),
      Keys.GenAI.requestModel: .string(request.model),
    ]

    if let maxOutputTokens = request.maxOutputTokens {
      attributes[Keys.GenAI.requestMaxTokens] = .int(maxOutputTokens)
    }
    if let temperature = request.temperature {
      attributes[Keys.GenAI.requestTemperature] = .double(temperature)
    }
    if let stream {
      attributes[Keys.GenAI.requestStream] = .bool(stream)
    }

    if let prompt = request.prompt, privacy.shouldCapture(promptCapture: request.promptCapture) {
      attributes.merge(
        redactedStringAttributes(
          original: prompt,
          lengthKey: Keys.Terra.promptLength,
          hmacKey: Keys.Terra.promptHMACSHA256,
          legacySHA256Key: Keys.Terra.promptSHA256,
          using: privacy
        )
      ) { _, new in new }
    }

    defer {
      let elapsed = ContinuousClock.now - startInstant
      let durationMs = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
      Runtime.shared.metrics.recordInference(durationMs: durationMs)
    }

    return try await withSpan(
      name: SpanNames.inference,
      kind: .internal,
      attributes: attributes,
      allowErrorMessageCapture: privacy.shouldCapture(promptCapture: request.promptCapture),
      body
    )
  }

  @discardableResult
  static func withStreamingInferenceSpan<R>(
    _ request: StreamingRequest,
    _ body: @Sendable (StreamingInferenceScope) async throws -> R
  ) async rethrows -> R {
    let streamingRequest = InferenceRequest(
      model: request.model,
      prompt: request.prompt,
      promptCapture: request.promptCapture,
      maxOutputTokens: request.maxOutputTokens,
      temperature: request.temperature
    )

    let startedAt = ContinuousClock.now
    return try await withInferenceSpan(streamingRequest, stream: true) { scope in
      let streamingScope = StreamingInferenceScope(scope: scope, startedAt: startedAt)
      if let expectedOutputTokens = request.expectedOutputTokens, expectedOutputTokens > 0 {
        streamingScope.setAttributes([Keys.Terra.streamOutputTokens: .int(expectedOutputTokens)])
      }
      defer { streamingScope.finish() }
      return try await body(streamingScope)
    }
  }

  @discardableResult
  static func withAgentInvocationSpan<R>(
    agent: AgentRequest,
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
      allowErrorMessageCapture: Runtime.shared.privacy.shouldCapture(promptCapture: .default),
      body
    )
  }

  @discardableResult
  static func withToolExecutionSpan<R>(
    tool: ToolRequest,
    _ body: @Sendable (Scope<ToolExecutionSpan>) async throws -> R
  ) async rethrows -> R {
    var attributes: [String: AttributeValue] = [
      Keys.GenAI.operationName: .string(OperationName.executeTool.rawValue),
      Keys.GenAI.toolName: .string(tool.name),
      Keys.GenAI.toolCallID: .string(tool.callID),
    ]
    if let type = tool.type {
      attributes[Keys.GenAI.toolType] = .string(type)
    }

    return try await withSpan(
      name: SpanNames.toolExecution,
      kind: .internal,
      attributes: attributes,
      allowErrorMessageCapture: Runtime.shared.privacy.shouldCapture(promptCapture: .default),
      body
    )
  }

  @discardableResult
  static func withEmbeddingSpan<R>(
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
      allowErrorMessageCapture: Runtime.shared.privacy.shouldCapture(promptCapture: .default),
      body
    )
  }

  @discardableResult
  static func withSafetyCheckSpan<R>(
    _ check: SafetyCheckRequest,
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
          hmacKey: Keys.Terra.safetySubjectHMACSHA256,
          legacySHA256Key: Keys.Terra.safetySubjectSHA256,
          using: privacy
        )
      ) { _, new in new }
    }

    return try await withSpan(
      name: SpanNames.safetyCheck,
      kind: .internal,
      attributes: attributes,
      allowErrorMessageCapture: privacy.shouldCapture(promptCapture: check.subjectCapture),
      body
    )
  }

  // MARK: - Internal

  private static func withSpan<R, Kind>(
    name: String,
    kind: SpanKind,
    attributes: [String: AttributeValue],
    allowErrorMessageCapture: Bool,
    _ body: @Sendable (Scope<Kind>) async throws -> R
  ) async rethrows -> R {
    let tracer = tracer()

    let spanBuilder = tracer.spanBuilder(spanName: name)
      .setSpanKind(spanKind: kind)

    for (key, value) in attributes {
      spanBuilder.setAttribute(key: key, value: value)
    }
    spanBuilder.setAttribute(key: Keys.Terra.thermalState, value: .string(Runtime.thermalStateLabel()))

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
        scope.recordError(error, captureMessage: allowErrorMessageCapture)
        throw error
      }
    }
  }

  final class StreamingInferenceScope: @unchecked Sendable {
    private let scope: Scope<InferenceSpan>
    private let startedAt: ContinuousClock.Instant
    private let lock = NSLock()
    private var firstTokenAt: ContinuousClock.Instant?
    private var outputTokenCount = 0
    private var chunkCount = 0

    init(scope: Scope<InferenceSpan>, startedAt: ContinuousClock.Instant) {
      self.scope = scope
      self.startedAt = startedAt
    }

    var span: any Span { scope.span }

    func addEvent(_ name: String, attributes: [String: AttributeValue] = [:]) {
      scope.addEvent(name, attributes: attributes)
    }

    func setAttributes(_ attributes: [String: AttributeValue]) {
      scope.setAttributes(attributes)
    }

    func recordError(_ error: any Error) {
      scope.recordError(error)
    }

    func recordToken(_ count: Int = 1) {
      guard count > 0 else { return }
      let now = ContinuousClock.now
      var shouldEmitFirstTokenEvent = false
      lock.lock()
      if firstTokenAt == nil {
        firstTokenAt = now
        shouldEmitFirstTokenEvent = true
      }
      outputTokenCount += count
      lock.unlock()

      if shouldEmitFirstTokenEvent {
        scope.addEvent(Keys.Terra.streamFirstTokenEvent)
      }
    }

    func recordOutputTokenCount(_ totalCount: Int) {
      guard totalCount >= 0 else { return }
      let now = ContinuousClock.now
      var shouldEmitFirstTokenEvent = false
      lock.lock()
      if totalCount > 0, firstTokenAt == nil {
        firstTokenAt = now
        shouldEmitFirstTokenEvent = true
      }
      outputTokenCount = totalCount
      lock.unlock()

      if shouldEmitFirstTokenEvent {
        scope.addEvent(Keys.Terra.streamFirstTokenEvent)
      }
    }

    func recordChunk() {
      let now = ContinuousClock.now
      var shouldEmitFirstTokenEvent = false
      lock.lock()
      chunkCount += 1
      if firstTokenAt == nil {
        firstTokenAt = now
        shouldEmitFirstTokenEvent = true
      }
      lock.unlock()

      if shouldEmitFirstTokenEvent {
        scope.addEvent(Keys.Terra.streamFirstTokenEvent)
      }
    }

    func recordFirstToken() {
      let now = ContinuousClock.now
      var shouldEmitFirstTokenEvent = false
      lock.lock()
      if firstTokenAt == nil {
        firstTokenAt = now
        shouldEmitFirstTokenEvent = true
      }
      lock.unlock()

      if shouldEmitFirstTokenEvent {
        scope.addEvent(Keys.Terra.streamFirstTokenEvent)
      }
    }

    func finish() {
      let now = ContinuousClock.now
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
        let ttft = startedAt.duration(to: firstTokenAt)
        attributes[Keys.Terra.streamTimeToFirstTokenMs] = .double(durationToMs(ttft))
      }
      if outputTokenCount > 0, let firstTokenAt {
        let generationDuration = firstTokenAt.duration(to: now)
        let generationSeconds = max(durationToSeconds(generationDuration), 0.000_001)
        attributes[Keys.Terra.streamTokensPerSecond] = .double(Double(outputTokenCount) / generationSeconds)
      }
      scope.setAttributes(attributes)
    }

    private func durationToMs(_ d: Duration) -> Double {
      Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1_000_000_000_000_000
    }

    private func durationToSeconds(_ d: Duration) -> Double {
      Double(d.components.seconds) + Double(d.components.attoseconds) / 1_000_000_000_000_000_000
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
    hmacKey: String,
    legacySHA256Key: String,
    using privacy: Privacy
  ) -> [String: AttributeValue] {
    switch privacy.redaction {
    case .drop:
      return [:]
    case .lengthOnly:
      return [lengthKey: .int(original.count)]
    case .hashHMACSHA256:
      var attributes: [String: AttributeValue] = [lengthKey: .int(original.count)]
      if Runtime.isHMACSHA256Available, let hash = Runtime.shared.hmacSHA256Hex(original) {
        attributes[hmacKey] = .string(hash)
        if let keyID = Runtime.shared.anonymizationKeyIDValue {
          attributes[Keys.Terra.anonymizationKeyID] = .string(keyID)
        }
      }
      if privacy.emitLegacySHA256Attributes, Runtime.isSHA256Available, let legacyHash = Runtime.sha256Hex(original) {
        attributes[legacySHA256Key] = .string(legacyHash)
      }
      return attributes
    case .hashSHA256:
      var attributes: [String: AttributeValue] = [lengthKey: .int(original.count)]
      if Runtime.isSHA256Available, let hash = Runtime.sha256Hex(original) {
        attributes[legacySHA256Key] = .string(hash)
      }
      return attributes
    }
  }
}
