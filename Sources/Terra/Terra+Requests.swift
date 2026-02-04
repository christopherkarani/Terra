import Foundation

extension Terra {
  // MARK: - Typed scope markers

  public enum InferenceSpan: Sendable {}
  public enum EmbeddingSpan: Sendable {}
  public enum AgentInvocationSpan: Sendable {}
  public enum ToolExecutionSpan: Sendable {}
  public enum SafetyCheckSpan: Sendable {}

  // MARK: - Requests

  public struct InferenceRequest: Sendable, Hashable {
    public var model: String
    public var prompt: String?
    public var promptCapture: CaptureIntent

    public var maxOutputTokens: Int?
    public var temperature: Double?
    public var stream: Bool?

    public init(
      model: String,
      prompt: String? = nil,
      promptCapture: CaptureIntent = .default,
      maxOutputTokens: Int? = nil,
      temperature: Double? = nil,
      stream: Bool? = nil
    ) {
      self.model = model
      self.prompt = prompt
      self.promptCapture = promptCapture
      self.maxOutputTokens = maxOutputTokens
      self.temperature = temperature
      self.stream = stream
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

    public init(name: String, id: String? = nil) {
      self.name = name
      self.id = id
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

    public init(id: String) {
      self.id = id
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
}

