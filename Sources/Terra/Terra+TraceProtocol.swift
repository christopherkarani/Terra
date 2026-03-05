import OpenTelemetryApi

extension Terra {
  package protocol Trace: Sendable {
    @discardableResult func event(_ name: String) -> Self
    @discardableResult func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self
    @discardableResult func emit<E: TerraEvent>(_ event: E) -> Self
    func recordError(_ error: any Error)
  }

  package struct InferenceTrace: Trace, Sendable {
    private let scope: Scope<InferenceSpan>

    init(scope: Scope<InferenceSpan>) {
      self.scope = scope
    }

    @discardableResult
    package func event(_ name: String) -> Self {
      scope.addEvent(name)
      return self
    }

    @discardableResult
    package func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self {
      scope.setAttributes([key.name: value.telemetryAttributeValue.openTelemetryValue])
      return self
    }

    @discardableResult
    package func emit<E: TerraEvent>(_ event: E) -> Self {
      var bag = AttributeBag()
      event.encode(into: &bag)
      scope.addEvent(String(describing: E.name), attributes: bag.openTelemetryAttributes)
      return self
    }

    package func recordError(_ error: any Error) {
      scope.recordError(error)
    }

    @discardableResult
    package func tokens(input: Int? = nil, output: Int? = nil) -> Self {
      var attributes: [String: AttributeValue] = [:]
      if let input {
        attributes[Keys.GenAI.usageInputTokens] = .int(input)
      }
      if let output {
        attributes[Keys.GenAI.usageOutputTokens] = .int(output)
      }
      if !attributes.isEmpty {
        scope.setAttributes(attributes)
      }
      return self
    }

    @discardableResult
    package func responseModel(_ value: String) -> Self {
      scope.setAttributes([Keys.GenAI.responseModel: .string(value)])
      return self
    }
  }

  package struct StreamingTrace: Trace, Sendable {
    private let scope: StreamingInferenceScope

    init(scope: StreamingInferenceScope) {
      self.scope = scope
    }

    @discardableResult
    package func event(_ name: String) -> Self {
      scope.addEvent(name)
      return self
    }

    @discardableResult
    package func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self {
      scope.setAttributes([key.name: value.telemetryAttributeValue.openTelemetryValue])
      return self
    }

    @discardableResult
    package func emit<E: TerraEvent>(_ event: E) -> Self {
      var bag = AttributeBag()
      event.encode(into: &bag)
      scope.addEvent(String(describing: E.name), attributes: bag.openTelemetryAttributes)
      return self
    }

    package func recordError(_ error: any Error) {
      scope.recordError(error)
    }

    @discardableResult
    package func chunk(tokens: Int = 1) -> Self {
      scope.recordChunk()
      if tokens > 0 {
        scope.recordToken(tokens)
      }
      return self
    }

    @discardableResult
    package func outputTokens(_ total: Int) -> Self {
      scope.recordOutputTokenCount(total)
      return self
    }

    @discardableResult
    package func firstToken() -> Self {
      scope.recordFirstToken()
      return self
    }
  }

  package struct EmbeddingTrace: Trace, Sendable {
    private let scope: Scope<EmbeddingSpan>

    init(scope: Scope<EmbeddingSpan>) {
      self.scope = scope
    }

    @discardableResult
    package func event(_ name: String) -> Self {
      scope.addEvent(name)
      return self
    }

    @discardableResult
    package func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self {
      scope.setAttributes([key.name: value.telemetryAttributeValue.openTelemetryValue])
      return self
    }

    @discardableResult
    package func emit<E: TerraEvent>(_ event: E) -> Self {
      var bag = AttributeBag()
      event.encode(into: &bag)
      scope.addEvent(String(describing: E.name), attributes: bag.openTelemetryAttributes)
      return self
    }

    package func recordError(_ error: any Error) {
      scope.recordError(error)
    }
  }

  package struct AgentTrace: Trace, Sendable {
    private let scope: Scope<AgentInvocationSpan>

    init(scope: Scope<AgentInvocationSpan>) {
      self.scope = scope
    }

    @discardableResult
    package func event(_ name: String) -> Self {
      scope.addEvent(name)
      return self
    }

    @discardableResult
    package func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self {
      scope.setAttributes([key.name: value.telemetryAttributeValue.openTelemetryValue])
      return self
    }

    @discardableResult
    package func emit<E: TerraEvent>(_ event: E) -> Self {
      var bag = AttributeBag()
      event.encode(into: &bag)
      scope.addEvent(String(describing: E.name), attributes: bag.openTelemetryAttributes)
      return self
    }

    package func recordError(_ error: any Error) {
      scope.recordError(error)
    }
  }

  package struct ToolTrace: Trace, Sendable {
    private let scope: Scope<ToolExecutionSpan>

    init(scope: Scope<ToolExecutionSpan>) {
      self.scope = scope
    }

    @discardableResult
    package func event(_ name: String) -> Self {
      scope.addEvent(name)
      return self
    }

    @discardableResult
    package func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self {
      scope.setAttributes([key.name: value.telemetryAttributeValue.openTelemetryValue])
      return self
    }

    @discardableResult
    package func emit<E: TerraEvent>(_ event: E) -> Self {
      var bag = AttributeBag()
      event.encode(into: &bag)
      scope.addEvent(String(describing: E.name), attributes: bag.openTelemetryAttributes)
      return self
    }

    package func recordError(_ error: any Error) {
      scope.recordError(error)
    }
  }

  package struct SafetyCheckTrace: Trace, Sendable {
    private let scope: Scope<SafetyCheckSpan>

    init(scope: Scope<SafetyCheckSpan>) {
      self.scope = scope
    }

    @discardableResult
    package func event(_ name: String) -> Self {
      scope.addEvent(name)
      return self
    }

    @discardableResult
    package func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self {
      scope.setAttributes([key.name: value.telemetryAttributeValue.openTelemetryValue])
      return self
    }

    @discardableResult
    package func emit<E: TerraEvent>(_ event: E) -> Self {
      var bag = AttributeBag()
      event.encode(into: &bag)
      scope.addEvent(String(describing: E.name), attributes: bag.openTelemetryAttributes)
      return self
    }

    package func recordError(_ error: any Error) {
      scope.recordError(error)
    }
  }
}
