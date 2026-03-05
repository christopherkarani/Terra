extension Terra {
  package enum Key {
    package static let model = AttributeKey<String>("gen_ai.request.model")
    package static let responseModel = AttributeKey<String>("gen_ai.response.model")
    package static let maxTokens = AttributeKey<Int>("gen_ai.request.max_tokens")
    package static let temperature = AttributeKey<Double>("gen_ai.request.temperature")
    package static let inputTokens = AttributeKey<Int>("gen_ai.usage.input_tokens")
    package static let outputTokens = AttributeKey<Int>("gen_ai.usage.output_tokens")
    package static let provider = AttributeKey<String>("gen_ai.provider.name")
    package static let runtime = AttributeKey<String>("terra.runtime")
    package static let agentName = AttributeKey<String>("gen_ai.agent.name")
    package static let toolName = AttributeKey<String>("gen_ai.tool.name")
    package static let timeToFirstToken = AttributeKey<Double>("terra.stream.time_to_first_token_ms")
    package static let tokensPerSecond = AttributeKey<Double>("terra.stream.tokens_per_second")
    package static let contentPolicy = AttributeKey<String>("terra.privacy.content_policy")

    @available(*, deprecated, renamed: "model")
    package static let requestModel = model
    @available(*, deprecated, renamed: "maxTokens")
    package static let requestMaxTokens = maxTokens
    @available(*, deprecated, renamed: "temperature")
    package static let requestTemperature = temperature
  }
}
