import OpenTelemetryApi

extension Terra {
  public protocol Trace: Sendable {
    @discardableResult func event(_ name: String) -> Self
    @discardableResult func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self
    @discardableResult func emit<E: TerraEvent>(_ event: E) -> Self
    func recordError(_ error: any Error)
  }

  public struct InferenceTrace: Trace, Sendable {
    private let scope: Scope<InferenceSpan>

    init(scope: Scope<InferenceSpan>) {
      self.scope = scope
    }

    @discardableResult
    public func event(_ name: String) -> Self {
      scope.addEvent(name)
      return self
    }

    @discardableResult
    public func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self {
      scope.setAttributes([key.name: value.telemetryAttributeValue.openTelemetryValue])
      return self
    }

    @discardableResult
    public func emit<E: TerraEvent>(_ event: E) -> Self {
      var bag = AttributeBag()
      event.encode(into: &bag)
      scope.addEvent(String(describing: E.name), attributes: bag.openTelemetryAttributes)
      return self
    }

    public func recordError(_ error: any Error) {
      scope.recordError(error)
    }

    @discardableResult
    public func tokens(input: Int? = nil, output: Int? = nil) -> Self {
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
    public func responseModel(_ value: String) -> Self {
      scope.setAttributes([Keys.GenAI.responseModel: .string(value)])
      return self
    }
  }

  public struct StreamingTrace: Trace, Sendable {
    private let scope: StreamingInferenceScope

    init(scope: StreamingInferenceScope) {
      self.scope = scope
    }

    @discardableResult
    public func event(_ name: String) -> Self {
      scope.addEvent(name)
      return self
    }

    @discardableResult
    public func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self {
      scope.setAttributes([key.name: value.telemetryAttributeValue.openTelemetryValue])
      return self
    }

    @discardableResult
    public func emit<E: TerraEvent>(_ event: E) -> Self {
      var bag = AttributeBag()
      event.encode(into: &bag)
      scope.addEvent(String(describing: E.name), attributes: bag.openTelemetryAttributes)
      return self
    }

    public func recordError(_ error: any Error) {
      scope.recordError(error)
    }

    @discardableResult
    public func chunk(tokens: Int = 1) -> Self {
      scope.recordChunk()
      if tokens > 0 {
        scope.recordToken(tokens)
      }
      return self
    }

    @discardableResult
    public func outputTokens(_ total: Int) -> Self {
      scope.recordOutputTokenCount(total)
      return self
    }

    @discardableResult
    public func firstToken() -> Self {
      scope.recordFirstToken()
      return self
    }
  }

  public struct EmbeddingTrace: Trace, Sendable {
    private let scope: Scope<EmbeddingSpan>

    init(scope: Scope<EmbeddingSpan>) {
      self.scope = scope
    }

    @discardableResult
    public func event(_ name: String) -> Self {
      scope.addEvent(name)
      return self
    }

    @discardableResult
    public func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self {
      scope.setAttributes([key.name: value.telemetryAttributeValue.openTelemetryValue])
      return self
    }

    @discardableResult
    public func emit<E: TerraEvent>(_ event: E) -> Self {
      var bag = AttributeBag()
      event.encode(into: &bag)
      scope.addEvent(String(describing: E.name), attributes: bag.openTelemetryAttributes)
      return self
    }

    public func recordError(_ error: any Error) {
      scope.recordError(error)
    }
  }

  public struct AgentTrace: Trace, Sendable {
    private let scope: Scope<AgentInvocationSpan>

    init(scope: Scope<AgentInvocationSpan>) {
      self.scope = scope
    }

    @discardableResult
    public func event(_ name: String) -> Self {
      scope.addEvent(name)
      return self
    }

    @discardableResult
    public func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self {
      scope.setAttributes([key.name: value.telemetryAttributeValue.openTelemetryValue])
      return self
    }

    @discardableResult
    public func emit<E: TerraEvent>(_ event: E) -> Self {
      var bag = AttributeBag()
      event.encode(into: &bag)
      scope.addEvent(String(describing: E.name), attributes: bag.openTelemetryAttributes)
      return self
    }

    public func recordError(_ error: any Error) {
      scope.recordError(error)
    }
  }

  public struct ToolTrace: Trace, Sendable {
    private let scope: Scope<ToolExecutionSpan>

    init(scope: Scope<ToolExecutionSpan>) {
      self.scope = scope
    }

    @discardableResult
    public func event(_ name: String) -> Self {
      scope.addEvent(name)
      return self
    }

    @discardableResult
    public func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self {
      scope.setAttributes([key.name: value.telemetryAttributeValue.openTelemetryValue])
      return self
    }

    @discardableResult
    public func emit<E: TerraEvent>(_ event: E) -> Self {
      var bag = AttributeBag()
      event.encode(into: &bag)
      scope.addEvent(String(describing: E.name), attributes: bag.openTelemetryAttributes)
      return self
    }

    public func recordError(_ error: any Error) {
      scope.recordError(error)
    }
  }

  public struct SafetyCheckTrace: Trace, Sendable {
    private let scope: Scope<SafetyCheckSpan>

    init(scope: Scope<SafetyCheckSpan>) {
      self.scope = scope
    }

    @discardableResult
    public func event(_ name: String) -> Self {
      scope.addEvent(name)
      return self
    }

    @discardableResult
    public func attribute<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value) -> Self {
      scope.setAttributes([key.name: value.telemetryAttributeValue.openTelemetryValue])
      return self
    }

    @discardableResult
    public func emit<E: TerraEvent>(_ event: E) -> Self {
      var bag = AttributeBag()
      event.encode(into: &bag)
      scope.addEvent(String(describing: E.name), attributes: bag.openTelemetryAttributes)
      return self
    }

    public func recordError(_ error: any Error) {
      scope.recordError(error)
    }
  }
}
