import Foundation

extension Terra {
  // MARK: - Typed scope markers

  enum InferenceSpan: Sendable {}
  enum EmbeddingSpan: Sendable {}
  enum AgentInvocationSpan: Sendable {}
  enum ToolExecutionSpan: Sendable {}
  enum SafetyCheckSpan: Sendable {}

  // MARK: - Requests

  package struct InferenceRequest: Sendable, Hashable {
    package var model: String
    package var prompt: String?
    package var includeContent: Bool

    package var maxOutputTokens: Int?
    package var temperature: Double?

    package init(
      model: String,
      prompt: String? = nil,
      includeContent: Bool = false,
      maxOutputTokens: Int? = nil,
      temperature: Double? = nil
    ) {
      self.model = model
      self.prompt = prompt
      self.includeContent = includeContent
      self.maxOutputTokens = maxOutputTokens
      self.temperature = temperature
    }

    package static func chat(model: String, prompt: String? = nil) -> Self {
      .init(model: model, prompt: prompt)
    }

    package func maxOutputTokens(_ value: Int) -> Self {
      var copy = self
      copy.maxOutputTokens = value
      return copy
    }

    package func temperature(_ value: Double) -> Self {
      var copy = self
      copy.temperature = value
      return copy
    }
  }

  package struct StreamingRequest: Sendable, Hashable {
    package var model: String
    package var prompt: String?
    package var includeContent: Bool
    package var maxOutputTokens: Int?
    package var temperature: Double?
    package var expectedOutputTokens: Int?

    package init(
      model: String,
      prompt: String? = nil,
      includeContent: Bool = false,
      maxOutputTokens: Int? = nil,
      temperature: Double? = nil,
      expectedOutputTokens: Int? = nil
    ) {
      self.model = model
      self.prompt = prompt
      self.includeContent = includeContent
      self.maxOutputTokens = maxOutputTokens
      self.temperature = temperature
      self.expectedOutputTokens = expectedOutputTokens
    }

    package static func chat(model: String, prompt: String? = nil) -> Self {
      .init(model: model, prompt: prompt)
    }

    package func maxOutputTokens(_ value: Int) -> Self {
      var copy = self
      copy.maxOutputTokens = value
      return copy
    }

    package func temperature(_ value: Double) -> Self {
      var copy = self
      copy.temperature = value
      return copy
    }

    package func expectedOutputTokens(_ value: Int) -> Self {
      var copy = self
      copy.expectedOutputTokens = value
      return copy
    }
  }

  package struct EmbeddingRequest: Sendable, Hashable {
    package var model: String
    package var inputCount: Int?

    package init(model: String, inputCount: Int? = nil) {
      self.model = model
      self.inputCount = inputCount
    }
  }

  package struct AgentRequest: Sendable, Hashable {
    package var name: String
    package var id: String?

    package init(name: String, id: String? = nil) {
      self.name = name
      self.id = id
    }
  }

  package struct ToolRequest: Sendable, Hashable {
    package var name: String
    package var callID: String
    package var type: String?

    package init(name: String, callID: String, type: String? = nil) {
      self.name = name
      self.callID = callID
      self.type = type
    }
  }

  package struct SafetyCheckRequest: Sendable, Hashable {
    package var name: String
    package var subject: String?
    package var includeContent: Bool

    package init(name: String, subject: String? = nil, includeContent: Bool = false) {
      self.name = name
      self.subject = subject
      self.includeContent = includeContent
    }
  }
}
