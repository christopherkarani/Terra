#if canImport(FoundationModels)
import FoundationModels
import TerraCore

@available(macOS 26.0, iOS 26.0, *)
internal struct TerraTracedSessionStreamChunk: Sendable {
  let content: String
  let outputTokenCount: Int?
}

@available(macOS 26.0, iOS 26.0, *)
internal protocol TerraTracedSessionBackend: Sendable {
  func respond(to prompt: String) async throws -> String
  func respond<T: Generable>(to prompt: String, generating type: T.Type) async throws -> T
  func streamResponse(to prompt: String) -> AsyncThrowingStream<TerraTracedSessionStreamChunk, Error>
  func transcriptEntries() -> [Any]
  func generationOptionsAttributes() -> [String: Terra.TelemetryAttributeValue]
}

@available(macOS 26.0, iOS 26.0, *)
internal final class FoundationModelsBackend: TerraTracedSessionBackend, @unchecked Sendable {
  private let session: LanguageModelSession
  private static let supportedTokenCountNames: Set<String> = [
    "outputTokenCount",
    "generatedTokenCount",
    "tokenCount",
    "tokensGenerated",
  ]

  init(model: SystemLanguageModel, instructions: String?) {
    if let instructions {
      session = LanguageModelSession(model: model, instructions: instructions)
    } else {
      session = LanguageModelSession(model: model)
    }
  }

  func respond(to prompt: String) async throws -> String {
    try await session.respond(to: prompt).content
  }

  func respond<T: Generable>(to prompt: String, generating type: T.Type) async throws -> T {
    try await session.respond(to: prompt, generating: type).content
  }

  func streamResponse(to prompt: String) -> AsyncThrowingStream<TerraTracedSessionStreamChunk, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let stream = session.streamResponse(to: prompt)
          for try await partial in stream {
            try Task.checkCancellation()
            continuation.yield(
              .init(
                content: partial.content,
                outputTokenCount: explicitOutputTokenCount(from: partial)
              )
            )
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  func transcriptEntries() -> [Any] {
    Self.extractTranscriptEntries(from: session)
  }

  func generationOptionsAttributes() -> [String: Terra.TelemetryAttributeValue] {
    Self.extractGenerationOptionAttributes(from: session)
  }

  private func explicitOutputTokenCount(from partial: Any) -> Int? {
    for child in Mirror(reflecting: partial).children {
      guard let label = child.label, Self.supportedTokenCountNames.contains(label) else { continue }
      if let intValue = child.value as? Int, intValue >= 0 {
        return intValue
      }
    }
    return nil
  }

  private static func extractTranscriptEntries(from session: LanguageModelSession) -> [Any] {
    for child in Mirror(reflecting: session).children {
      guard let label = child.label?.lowercased() else { continue }
      guard label.contains("transcript") || label.contains("history") else { continue }
      return collectionElements(child.value)
    }
    return []
  }

  private static func extractGenerationOptionAttributes(
    from session: LanguageModelSession
  ) -> [String: Terra.TelemetryAttributeValue] {
    var attributes: [String: Terra.TelemetryAttributeValue] = [:]
    let candidates = Mirror(reflecting: session).children

    for child in candidates {
      guard let label = child.label?.lowercased() else { continue }
      guard label.contains("generation") || label.contains("option") || label.contains("config") else { continue }
      populateGenerationAttributes(from: child.value, into: &attributes)
    }
    populateGenerationAttributes(from: session, into: &attributes)

    return attributes
  }

  private static func populateGenerationAttributes(
    from source: Any,
    into attributes: inout [String: Terra.TelemetryAttributeValue]
  ) {
    for child in Mirror(reflecting: source).children {
      guard let label = child.label?.lowercased() else { continue }
      if (label.contains("temperature") || label == "temp"), let value = asDouble(child.value) {
        attributes[Terra.Keys.GenAI.requestTemperature] = .double(value)
      } else if (label.contains("maxtokens") || label.contains("maxoutputtokens")), let value = asInt(child.value) {
        attributes[Terra.Keys.GenAI.requestMaxTokens] = .int(value)
      } else if label.contains("sampling"), let value = asString(child.value) {
        attributes["terra.fm.generation.sampling_mode"] = .string(value)
      }
    }
  }

  private static func asString(_ value: Any) -> String? {
    if let value = value as? String {
      return value
    }
    let reflected = String(describing: value)
    return reflected == "nil" ? nil : reflected
  }

  private static func asInt(_ value: Any) -> Int? {
    if let value = value as? Int {
      return value
    }
    if let value = value as? Int32 {
      return Int(value)
    }
    if let value = value as? Int64 {
      return Int(value)
    }
    return nil
  }

  private static func asDouble(_ value: Any) -> Double? {
    if let value = value as? Double {
      return value
    }
    if let value = value as? Float {
      return Double(value)
    }
    return nil
  }

  private static func collectionElements(_ value: Any) -> [Any] {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .collection else { return [] }
    return mirror.children.map(\.value)
  }
}

@available(macOS 26.0, iOS 26.0, *)
public final class TerraTracedSession {
  private let backend: any TerraTracedSessionBackend
  public let modelIdentifier: Terra.ModelID

  public init(
    model: SystemLanguageModel = .default,
    instructions: String? = nil,
    modelIdentifier: Terra.ModelID = "apple/foundation-model"
  ) {
    self.modelIdentifier = modelIdentifier
    self.backend = FoundationModelsBackend(model: model, instructions: instructions)
  }

  internal init(
    modelIdentifier: Terra.ModelID = "apple/foundation-model",
    backend: any TerraTracedSessionBackend
  ) {
    self.modelIdentifier = modelIdentifier
    self.backend = backend
  }

  /// Respond to a prompt with auto-tracing.
  public func respond(to prompt: String, promptCapture: Terra.CapturePolicy = .default) async throws -> String {
    var call = makeInferenceCall(prompt: prompt, promptCapture: promptCapture)
    call = call.attributes { attributes in
      applyGenerationAttributes(from: backend.generationOptionsAttributes(), to: &attributes)
    }

    return try await call.execute { trace in
      let before = backend.transcriptEntries()
      do {
        let response = try await backend.respond(to: prompt)
        let diff = Self.inspectTranscriptDiff(before: before, after: backend.transcriptEntries())
        applyToolDiff(diff, captureContent: promptCapture == .includeContent, to: trace)
        if let violation = diff.guardrailViolationType {
          await emitGuardrailSpan(
            violationType: violation,
            prompt: prompt,
            promptCapture: promptCapture
          )
        }
        return response
      } catch {
        if Self.isGuardrailError(error) {
          await emitGuardrailSpan(
            violationType: String(reflecting: Swift.type(of: error)),
            prompt: prompt,
            promptCapture: promptCapture
          )
        }
        throw error
      }
    }
  }

  /// Respond with structured output (@Generable type).
  public func respond<T: Generable>(
    to prompt: String,
    generating type: T.Type,
    promptCapture: Terra.CapturePolicy = .default
  ) async throws -> T {
    var call = makeInferenceCall(prompt: prompt, promptCapture: promptCapture)
      .attribute(.init("terra.foundation_models.response_type"), String(describing: T.self))
    call = call.attributes { attributes in
      applyGenerationAttributes(from: backend.generationOptionsAttributes(), to: &attributes)
    }

    return try await call.execute { trace in
      let before = backend.transcriptEntries()
      do {
        let response = try await backend.respond(to: prompt, generating: type)
        let diff = Self.inspectTranscriptDiff(before: before, after: backend.transcriptEntries())
        applyToolDiff(diff, captureContent: promptCapture == .includeContent, to: trace)
        if let violation = diff.guardrailViolationType {
          await emitGuardrailSpan(
            violationType: violation,
            prompt: prompt,
            promptCapture: promptCapture
          )
        }
        return response
      } catch {
        if Self.isGuardrailError(error) {
          await emitGuardrailSpan(
            violationType: String(reflecting: Swift.type(of: error)),
            prompt: prompt,
            promptCapture: promptCapture
          )
        }
        throw error
      }
    }
  }

  /// Stream a response with auto-tracing.
  public func streamResponse(to prompt: String, promptCapture: Terra.CapturePolicy = .default) -> AsyncThrowingStream<String, Error> {
    let request = Terra.StreamingRequest(
      model: modelIdentifier.rawValue,
      prompt: prompt,
      includeContent: promptCapture == .includeContent,
    )

    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          try await Terra
            .stream(request)
            .provider("apple/foundation-model")
            .runtime("foundation_models")
            .attribute(.init(Terra.Keys.Terra.autoInstrumented), true)
            .execute { streamScope in
              let stream = backend.streamResponse(to: prompt)
              for try await chunk in stream {
                try Task.checkCancellation()
                streamScope.chunk(tokens: 0)
                if let explicitCount = chunk.outputTokenCount {
                  streamScope.outputTokens(explicitCount)
                }
                continuation.yield(chunk.content)
              }
            }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  private func makeInferenceCall(prompt: String, promptCapture: Terra.CapturePolicy) -> Terra.InferenceCall {
    var call = Terra
      .inference(model: modelIdentifier.rawValue, prompt: prompt)
      .provider("apple/foundation-model")
      .runtime("foundation_models")
      .attribute(.init(Terra.Keys.Terra.autoInstrumented), true)
    if promptCapture == .includeContent {
      call = call.includeContent()
    }
    return call
  }

  private func emitGuardrailSpan(
    violationType: String,
    prompt: String,
    promptCapture: Terra.CapturePolicy
  ) async {
    var call = Terra
      .safetyCheck(name: "foundation-model-guardrail", subject: prompt)
      .provider("apple/foundation-model")
      .runtime("foundation_models")
      .attribute(.init(Terra.Keys.Terra.autoInstrumented), true)
      .attribute(.init("terra.fm.guardrail.violation_type"), violationType)
    if promptCapture == .includeContent {
      call = call.includeContent()
    }
    _ = await call.execute { () }
  }

  private func applyGenerationAttributes(
    from attributes: [String: Terra.TelemetryAttributeValue],
    to bag: inout Terra.AttributeBag
  ) {
    for (key, value) in attributes {
      switch value {
      case .string(let value):
        bag.set(.init(key), value)
      case .int(let value):
        bag.set(.init(key), value)
      case .double(let value):
        bag.set(.init(key), value)
      case .bool(let value):
        bag.set(.init(key), value)
      }
    }
  }

  private func applyToolDiff(
    _ diff: TranscriptDiff,
    captureContent: Bool,
    to trace: Terra.InferenceTrace
  ) {
    let toolNames = diff.toolCalls.map(\.name)

    for call in diff.toolCalls {
      trace.emit(
        ToolCallEvent(
          name: call.name,
          arguments: captureContent ? call.arguments : nil
        )
      )
    }
    for result in diff.toolResults {
      trace.emit(
        ToolResultEvent(
          name: result.name,
          result: captureContent ? result.result : nil
        )
      )
    }

    trace.attribute(.init("terra.fm.tools.called"), toolNames.joined(separator: ","))
    trace.attribute(.init("terra.fm.tool_call_count"), diff.toolCalls.count)
  }

  private static func isGuardrailError(_ error: any Error) -> Bool {
    let typeName = String(reflecting: type(of: error)).lowercased()
    let message = String(describing: error).lowercased()
    return typeName.contains("guardrail")
      || typeName.contains("safety")
      || message.contains("guardrail")
      || message.contains("safety")
      || message.contains("violation")
  }

  private struct TranscriptDiff {
    struct ToolCall: Sendable {
      let name: String
      let arguments: String?
    }

    struct ToolResult: Sendable {
      let name: String
      let result: String?
    }

    var toolCalls: [ToolCall]
    var toolResults: [ToolResult]
    var guardrailViolationType: String?
  }

  private static func inspectTranscriptDiff(before: [Any], after: [Any]) -> TranscriptDiff {
    let newEntries = after.dropFirst(before.count)
    var diff = TranscriptDiff(toolCalls: [], toolResults: [], guardrailViolationType: nil)

    for entry in newEntries {
      if let toolCall = parseToolCall(from: entry) {
        diff.toolCalls.append(toolCall)
      }
      if let toolResult = parseToolResult(from: entry) {
        diff.toolResults.append(toolResult)
      }
      if let violation = parseGuardrailViolation(from: entry) {
        diff.guardrailViolationType = violation
      }
    }

    return diff
  }

  private static func parseToolCall(from entry: Any) -> TranscriptDiff.ToolCall? {
    let typeName = String(reflecting: type(of: entry)).lowercased()
    let name = lookupString(
      in: entry,
      keys: ["toolname", "name", "functionname", "tool", "callname"]
    )
    let arguments = lookupString(
      in: entry,
      keys: ["arguments", "args", "parameters", "input"]
    )

    let looksLikeToolCall =
      typeName.contains("toolcall")
      || typeName.contains("functioncall")
      || lookupAny(in: entry, keys: ["toolcall", "functioncall"]) != nil
      || (name != nil && arguments != nil)

    guard looksLikeToolCall, let name else { return nil }
    return .init(name: name, arguments: arguments)
  }

  private static func parseToolResult(from entry: Any) -> TranscriptDiff.ToolResult? {
    let typeName = String(reflecting: type(of: entry)).lowercased()
    let name = lookupString(
      in: entry,
      keys: ["toolname", "name", "functionname", "tool", "callname"]
    )
    let result = lookupString(
      in: entry,
      keys: ["result", "output", "response", "value"]
    )

    let looksLikeToolResult =
      typeName.contains("toolresult")
      || lookupAny(in: entry, keys: ["toolresult"]) != nil
      || (name != nil && result != nil)

    guard looksLikeToolResult, let name else { return nil }
    return .init(name: name, result: result)
  }

  private static func parseGuardrailViolation(from entry: Any) -> String? {
    let typeName = String(reflecting: type(of: entry)).lowercased()
    if typeName.contains("guardrail") || typeName.contains("violation") {
      return String(reflecting: type(of: entry))
    }
    if let marker = lookupString(in: entry, keys: ["guardrail", "violation"]) {
      return marker
    }
    return nil
  }

  private static func lookupString(in source: Any, keys: [String]) -> String? {
    if let anyValue = lookupAny(in: source, keys: keys) {
      if let value = anyValue as? String {
        return value
      }
      let value = String(describing: anyValue)
      if value != "nil" {
        return value
      }
    }
    return nil
  }

  private static func lookupAny(in source: Any, keys: [String]) -> Any? {
    let lowered = keys.map { $0.lowercased() }
    for child in Mirror(reflecting: source).children {
      guard let label = child.label?.lowercased() else { continue }
      if lowered.contains(where: { label.contains($0) }) {
        return child.value
      }
    }
    return nil
  }

  private struct ToolCallEvent: Terra.TerraEvent {
    static var name: StaticString { "tool_call" }

    let name: String
    let arguments: String?

    func encode(into attributes: inout Terra.AttributeBag) {
      attributes.set(.init("terra.fm.tool.name"), name)
      if let arguments {
        attributes.set(.init("terra.fm.tool.arguments"), arguments)
      }
    }
  }

  private struct ToolResultEvent: Terra.TerraEvent {
    static var name: StaticString { "tool_result" }

    let name: String
    let result: String?

    func encode(into attributes: inout Terra.AttributeBag) {
      attributes.set(.init("terra.fm.tool.name"), name)
      if let result {
        attributes.set(.init("terra.fm.tool.result"), result)
      }
    }
  }
}

#else

// Stub so the module always compiles
enum TerraFoundationModelsPlaceholder {
  // FoundationModels framework not available on this platform/SDK
}

#endif
