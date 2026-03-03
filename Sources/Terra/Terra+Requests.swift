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

    public init(
      model: String,
      prompt: String? = nil,
      promptCapture: CaptureIntent = .default,
      maxOutputTokens: Int? = nil,
      temperature: Double? = nil
    ) {
      self.model = model
      self.prompt = prompt
      self.promptCapture = promptCapture
      self.maxOutputTokens = maxOutputTokens
      self.temperature = temperature
    }

    public static func chat(model: String, prompt: String? = nil) -> Self {
      .init(model: model, prompt: prompt)
    }

    public func maxOutputTokens(_ value: Int) -> Self {
      var copy = self
      copy.maxOutputTokens = value
      return copy
    }

    public func temperature(_ value: Double) -> Self {
      var copy = self
      copy.temperature = value
      return copy
    }
  }

  public struct StreamingRequest: Sendable, Hashable {
    public var model: String
    public var prompt: String?
    public var promptCapture: CaptureIntent
    public var maxOutputTokens: Int?
    public var temperature: Double?
    public var expectedOutputTokens: Int?

    public init(
      model: String,
      prompt: String? = nil,
      promptCapture: CaptureIntent = .default,
      maxOutputTokens: Int? = nil,
      temperature: Double? = nil,
      expectedOutputTokens: Int? = nil
    ) {
      self.model = model
      self.prompt = prompt
      self.promptCapture = promptCapture
      self.maxOutputTokens = maxOutputTokens
      self.temperature = temperature
      self.expectedOutputTokens = expectedOutputTokens
    }

    public static func chat(model: String, prompt: String? = nil) -> Self {
      .init(model: model, prompt: prompt)
    }

    public func maxOutputTokens(_ value: Int) -> Self {
      var copy = self
      copy.maxOutputTokens = value
      return copy
    }

    public func temperature(_ value: Double) -> Self {
      var copy = self
      copy.temperature = value
      return copy
    }

    public func expectedOutputTokens(_ value: Int) -> Self {
      var copy = self
      copy.expectedOutputTokens = value
      return copy
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

  public struct AgentRequest: Sendable, Hashable {
    public var name: String
    public var id: String?

    public init(name: String, id: String? = nil) {
      self.name = name
      self.id = id
    }
  }

  public struct ToolRequest: Sendable, Hashable {
    public var name: String
    public var callID: String
    public var type: String?

    public init(name: String, callID: String, type: String? = nil) {
      self.name = name
      self.callID = callID
      self.type = type
    }
  }

  public struct SafetyCheckRequest: Sendable, Hashable {
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
