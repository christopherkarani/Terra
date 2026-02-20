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
  public static func withInferenceSpan<R>(
    _ request: InferenceRequest,
    _ body: @Sendable (Scope<InferenceSpan>) async throws -> R
  ) async rethrows -> R {
    let privacy = Runtime.shared.privacy
    let startTime = Date()

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

    defer {
      let durationMs = Date().timeIntervalSince(startTime) * 1000
      Runtime.shared.metrics.recordInference(durationMs: durationMs)
    }

    return try await withSpan(
      name: SpanNames.inference,
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

    let startedAt = Date()
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
    mergedAttributes[Keys.Terra.thermalState] = .string(Runtime.thermalStateLabel())

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
    private let startedAt: Date
    private let lock = NSLock()
    private var firstTokenAt: Date?
    private var outputTokenCount = 0
    private var chunkCount = 0

    init(scope: Scope<InferenceSpan>, startedAt: Date) {
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

    public func recordToken(_ count: Int = 1, at timestamp: Date = Date()) {
      guard count > 0 else { return }
      var shouldEmitFirstTokenEvent = false
      lock.lock()
      if firstTokenAt == nil {
        firstTokenAt = timestamp
        shouldEmitFirstTokenEvent = true
      }
      outputTokenCount += count
      lock.unlock()

      if shouldEmitFirstTokenEvent {
        scope.addEvent(Keys.Terra.streamFirstTokenEvent)
      }
    }

    public func recordOutputTokenCount(_ totalCount: Int, at timestamp: Date = Date()) {
      guard totalCount >= 0 else { return }
      var shouldEmitFirstTokenEvent = false
      lock.lock()
      if totalCount > 0, firstTokenAt == nil {
        firstTokenAt = timestamp
        shouldEmitFirstTokenEvent = true
      }
      outputTokenCount = totalCount
      lock.unlock()

      if shouldEmitFirstTokenEvent {
        scope.addEvent(Keys.Terra.streamFirstTokenEvent)
      }
    }

    public func recordChunk(at timestamp: Date = Date()) {
      var shouldEmitFirstTokenEvent = false
      lock.lock()
      chunkCount += 1
      if firstTokenAt == nil {
        firstTokenAt = timestamp
        shouldEmitFirstTokenEvent = true
      }
      lock.unlock()

      if shouldEmitFirstTokenEvent {
        scope.addEvent(Keys.Terra.streamFirstTokenEvent)
      }
    }

    func finish(finishedAt: Date = Date()) {
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
        attributes[Keys.Terra.streamTimeToFirstTokenMs] = .double(firstTokenAt.timeIntervalSince(startedAt) * 1000)
      }
      if outputTokenCount > 0, let firstTokenAt {
        let generationSeconds = max(finishedAt.timeIntervalSince(firstTokenAt), 0.000_001)
        attributes[Keys.Terra.streamTokensPerSecond] = .double(Double(outputTokenCount) / generationSeconds)
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
      if Runtime.isSHA256Available, let hash = Runtime.sha256Hex(original) {
        attributes[hashKey] = .string(hash)
      }
      return attributes
    }
  }
}
