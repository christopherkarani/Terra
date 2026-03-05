import OpenTelemetryApi

extension Terra.Scope {
  /// Sets a normalized runtime name, e.g. "mlx" or "foundation_models".
  func setRuntime(_ runtime: String) {
    setAttributes([Terra.Keys.Terra.runtime: .string(runtime)])
  }
}

extension Terra.Scope where Kind == Terra.InferenceSpan {
  /// Sets the provider name using the GenAI semantic convention key.
  func setProvider(_ provider: String) {
    setAttributes([Terra.Keys.GenAI.providerName: .string(provider)])
  }

  /// Sets the concrete response model identifier.
  func setResponseModel(_ model: String) {
    setAttributes([Terra.Keys.GenAI.responseModel: .string(model)])
  }

  /// Sets input/output token usage counts when available.
  func setTokenUsage(input: Int? = nil, output: Int? = nil) {
    var attributes: [String: AttributeValue] = [:]
    if let input {
      attributes[Terra.Keys.GenAI.usageInputTokens] = .int(input)
    }
    if let output {
      attributes[Terra.Keys.GenAI.usageOutputTokens] = .int(output)
    }
    guard !attributes.isEmpty else { return }
    setAttributes(attributes)
  }
}

extension Terra.StreamingInferenceScope {
  /// Sets a normalized runtime name, e.g. "foundation_models".
  func setRuntime(_ runtime: String) {
    setAttributes([Terra.Keys.Terra.runtime: .string(runtime)])
  }

  /// Records a streamed chunk and optionally its token count in one call.
  func recordChunk(tokens: Int) {
    recordChunk()
    guard tokens > 0 else { return }
    recordToken(tokens)
  }
}
