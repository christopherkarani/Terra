import Foundation
import OpenTelemetryApi

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
    let clock = ContinuousClock()
    let start = clock.now

    var attributes: [String: AttributeValue] = [
      Keys.GenAI.operationName: .string(OperationName.inference.rawValue),
      Keys.GenAI.model: .string(request.model),
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
      let durationMs = max(0, milliseconds(from: start.duration(to: clock.now)))
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
      Keys.GenAI.model: .string(request.model),
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

    let spanBuilder = tracer.spanBuilder(spanName: name)
      .setSpanKind(spanKind: kind)

    for (key, value) in attributes {
      spanBuilder.setAttribute(key: key, value: value)
    }

    let span = spanBuilder.startSpan()
    defer { span.end() }

    let scope = Scope<Kind>(span: span)

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

  private static func milliseconds(from duration: Duration) -> Double {
    let components = duration.components
    return (Double(components.seconds) * 1_000) + (Double(components.attoseconds) / 1_000_000_000_000_000)
  }
}
