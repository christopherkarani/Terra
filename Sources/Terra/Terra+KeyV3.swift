extension Terra {
  public enum Key {
    public static let model = AttributeKey<String>("gen_ai.request.model")
    public static let responseModel = AttributeKey<String>("gen_ai.response.model")
    public static let maxTokens = AttributeKey<Int>("gen_ai.request.max_tokens")
    public static let temperature = AttributeKey<Double>("gen_ai.request.temperature")
    public static let inputTokens = AttributeKey<Int>("gen_ai.usage.input_tokens")
    public static let outputTokens = AttributeKey<Int>("gen_ai.usage.output_tokens")
    public static let provider = AttributeKey<String>("gen_ai.provider.name")
    public static let runtime = AttributeKey<String>("terra.runtime")
    public static let agentName = AttributeKey<String>("gen_ai.agent.name")
    public static let toolName = AttributeKey<String>("gen_ai.tool.name")
    public static let timeToFirstToken = AttributeKey<Double>("terra.stream.time_to_first_token_ms")
    public static let tokensPerSecond = AttributeKey<Double>("terra.stream.tokens_per_second")
    public static let contentPolicy = AttributeKey<String>("terra.privacy.content_policy")

    @available(*, deprecated, renamed: "model")
    public static let requestModel = model
    @available(*, deprecated, renamed: "maxTokens")
    public static let requestMaxTokens = maxTokens
    @available(*, deprecated, renamed: "temperature")
    public static let requestTemperature = temperature
  }
}
