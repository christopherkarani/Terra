import Foundation

extension Terra {
  // MARK: - Typed scope markers

  public enum InferenceSpan: Sendable {}
  public enum ModelLoadSpan: Sendable {}
  public enum InferenceStageSpan: Sendable {}
  public enum StreamingLifecycleSpan: Sendable {}
  public enum EmbeddingSpan: Sendable {}
  public enum AgentInvocationSpan: Sendable {}
  public enum ToolExecutionSpan: Sendable {}
  public enum SafetyCheckSpan: Sendable {}

  public enum InferenceStage: String, Sendable, Hashable, CaseIterable {
    case promptEval = "prompt_eval"
    case decode
    case streamLifecycle = "stream_lifecycle"
  }

  // MARK: - Requests

  public struct ModelFingerprint: Sendable, Hashable {
    public var modelID: String
    public var runtime: RuntimeKind
    public var quantization: String?
    public var tokenizerRevision: String?
    public var backendRevision: String?

    public init(
      modelID: String,
      runtime: RuntimeKind,
      quantization: String? = nil,
      tokenizerRevision: String? = nil,
      backendRevision: String? = nil
    ) {
      self.modelID = modelID
      self.runtime = runtime
      self.quantization = quantization
      self.tokenizerRevision = tokenizerRevision
      self.backendRevision = backendRevision
    }

    var attributeValue: String {
      var parts: [String] = [
        "model=\(modelID)",
        "runtime=\(runtime.rawValue)"
      ]
      if let quantization, !quantization.isEmpty {
        parts.append("quant=\(quantization)")
      }
      if let tokenizerRevision, !tokenizerRevision.isEmpty {
        parts.append("tokenizer=\(tokenizerRevision)")
      }
      if let backendRevision, !backendRevision.isEmpty {
        parts.append("backend=\(backendRevision)")
      }
      return parts.joined(separator: "|")
    }
  }

  public struct InferenceRequest: Sendable, Hashable {
    public var model: String
    public var prompt: String?
    public var promptCapture: CaptureIntent
    public var runtime: RuntimeKind?
    public var requestID: String
    public var modelFingerprint: ModelFingerprint?

    public var maxOutputTokens: Int?
    public var temperature: Double?
    public var stream: Bool?

    // Content telemetry (privacy-governed)
    public var systemPrompt: String?
    public var completionText: String?
    public var thinkingText: String?
    public var finishReason: String?

    public init(
      model: String,
      prompt: String? = nil,
      promptCapture: CaptureIntent = .default,
      runtime: RuntimeKind? = nil,
      requestID: String = UUID().uuidString,
      modelFingerprint: ModelFingerprint? = nil,
      maxOutputTokens: Int? = nil,
      temperature: Double? = nil,
      stream: Bool? = nil,
      systemPrompt: String? = nil,
      completionText: String? = nil,
      thinkingText: String? = nil,
      finishReason: String? = nil
    ) {
      self.model = model
      self.prompt = prompt
      self.promptCapture = promptCapture
      self.runtime = runtime
      self.requestID = requestID
      self.modelFingerprint = modelFingerprint
      self.maxOutputTokens = maxOutputTokens
      self.temperature = temperature
      self.stream = stream
      self.systemPrompt = systemPrompt
      self.completionText = completionText
      self.thinkingText = thinkingText
      self.finishReason = finishReason
    }
  }

  public struct EmbeddingRequest: Sendable, Hashable {
    public var model: String
    public var inputCount: Int?

    public init(model: String, inputCount: Int? = nil) {
      self.model = model
      self.inputCount = inputCount
    }
  }

  public struct Agent: Sendable, Hashable {
    public var name: String
    public var id: String?
    public var delegationPrompt: String?
    public var delegationCapture: CaptureIntent

    public init(
      name: String,
      id: String? = nil,
      delegationPrompt: String? = nil,
      delegationCapture: CaptureIntent = .default
    ) {
      self.name = name
      self.id = id
      self.delegationPrompt = delegationPrompt
      self.delegationCapture = delegationCapture
    }
  }

  public struct Tool: Sendable, Hashable {
    public var name: String
    public var type: String?

    public init(name: String, type: String? = nil) {
      self.name = name
      self.type = type
    }
  }

  public struct ToolCall: Sendable, Hashable {
    public var id: String
    public var input: String?
    public var output: String?
    public var contentCapture: CaptureIntent

    public init(
      id: String,
      input: String? = nil,
      output: String? = nil,
      contentCapture: CaptureIntent = .default
    ) {
      self.id = id
      self.input = input
      self.output = output
      self.contentCapture = contentCapture
    }
  }

  public struct SafetyCheck: Sendable, Hashable {
    public var name: String
    public var subject: String?
    public var subjectCapture: CaptureIntent

    public init(name: String, subject: String? = nil, subjectCapture: CaptureIntent = .default) {
      self.name = name
      self.subject = subject
      self.subjectCapture = subjectCapture
    }
  }

  public enum RecommendationKind: String, Sendable, Hashable, CaseIterable {
    case thermalSlowdown = "thermal_slowdown"
    case promptCacheMiss = "prompt_cache_miss"
    case modelSwapRegression = "model_swap_regression"
    case stalledToken = "stalled_token"
    case custom = "custom"
  }

  public struct Recommendation: Sendable, Hashable {
    public var id: String?
    public var kind: RecommendationKind
    public var confidence: Double
    public var action: String
    public var reason: String
    public var attributes: [String: String]

    public init(
      id: String? = nil,
      kind: RecommendationKind,
      confidence: Double,
      action: String,
      reason: String,
      attributes: [String: String] = [:]
    ) {
      self.id = id
      self.kind = kind
      self.confidence = confidence
      self.action = action
      self.reason = reason
      self.attributes = attributes
    }
  }

  public typealias RecommendationSink = @Sendable (Recommendation) -> Void
}
