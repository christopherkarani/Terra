import Testing
import Foundation
@testable import TerraHTTPInstrument

// MARK: - AIRequestParser Tests

@Test("OpenAI request format parses model, max_tokens, temperature, stream")
func openAIRequestParsing() throws {
  let body = #"{"model": "gpt-4", "max_tokens": 100, "temperature": 0.7, "stream": true}"#
  let data = try #require(body.data(using: .utf8))
  let result = try #require(AIRequestParser.parse(body: data))

  #expect(result.model == "gpt-4")
  #expect(result.maxTokens == 100)
  #expect(result.temperature == 0.7)
  #expect(result.stream == true)
}

@Test("Anthropic request format parses model and max_tokens")
func anthropicRequestParsing() throws {
  let body = #"{"model": "claude-3-opus", "max_tokens": 4096}"#
  let data = try #require(body.data(using: .utf8))
  let result = try #require(AIRequestParser.parse(body: data))

  #expect(result.model == "claude-3-opus")
  #expect(result.maxTokens == 4096)
  #expect(result.temperature == nil)
  #expect(result.stream == nil)
}

@Test("OpenAI new format parses max_completion_tokens")
func openAINewFormatRequestParsing() throws {
  let body = #"{"model": "gpt-4o", "max_completion_tokens": 200}"#
  let data = try #require(body.data(using: .utf8))
  let result = try #require(AIRequestParser.parse(body: data))

  #expect(result.model == "gpt-4o")
  #expect(result.maxTokens == 200)
}

@Test("HuggingFace format parses max_new_tokens")
func huggingFaceRequestParsing() throws {
  let body = #"{"model": "llama", "max_new_tokens": 512}"#
  let data = try #require(body.data(using: .utf8))
  let result = try #require(AIRequestParser.parse(body: data))

  #expect(result.model == "llama")
  #expect(result.maxTokens == 512)
}

@Test("Floating max_tokens values are accepted when integral")
func floatingMaxTokensAreAccepted() throws {
  let body = #"{"model": "gpt-4", "max_tokens": 128.0}"#
  let data = try #require(body.data(using: .utf8))
  let result = try #require(AIRequestParser.parse(body: data))

  #expect(result.maxTokens == 128)
}

@Test("Empty body returns nil")
func emptyBodyReturnsNil() throws {
  let data = Data()
  let result = AIRequestParser.parse(body: data)
  #expect(result == nil)
}

@Test("Invalid JSON returns nil")
func invalidJSONRequestReturnsNil() throws {
  let body = "not json at all {"
  let data = try #require(body.data(using: .utf8))
  let result = AIRequestParser.parse(body: data)
  #expect(result == nil)
}

@Test("JSON with no recognized AI fields returns nil")
func noRecognizedFieldsRequestReturnsNil() throws {
  let body = #"{"foo": "bar", "count": 42}"#
  let data = try #require(body.data(using: .utf8))
  let result = AIRequestParser.parse(body: data)
  #expect(result == nil)
}

@Test("Integer temperature is coerced to Double")
func integerTemperatureIsCoerced() throws {
  let body = #"{"model": "gpt-4", "temperature": 1}"#
  let data = try #require(body.data(using: .utf8))
  let result = try #require(AIRequestParser.parse(body: data))

  #expect(result.temperature == 1.0)
}

@Test("Request body larger than 10 MiB is rejected")
func oversizedRequestBodyReturnsNil() throws {
  let oversizedPayload = Data(repeating: 0x61, count: AIRequestParser.maxBodySizeBytes + 1)
  let result = AIRequestParser.parse(body: oversizedPayload)
  #expect(result == nil)
}

// MARK: - AIResponseParser Tests

@Test("OpenAI response format parses model and usage tokens")
func openAIResponseParsing() throws {
  let body = #"{"model": "gpt-4", "usage": {"prompt_tokens": 10, "completion_tokens": 20}}"#
  let data = try #require(body.data(using: .utf8))
  let result = try #require(AIResponseParser.parse(data: data))

  #expect(result.model == "gpt-4")
  #expect(result.inputTokens == 10)
  #expect(result.outputTokens == 20)
}

@Test("Anthropic response format parses input and output tokens")
func anthropicResponseParsing() throws {
  let body = #"{"model": "claude-3", "usage": {"input_tokens": 15, "output_tokens": 25}}"#
  let data = try #require(body.data(using: .utf8))
  let result = try #require(AIResponseParser.parse(data: data))

  #expect(result.model == "claude-3")
  #expect(result.inputTokens == 15)
  #expect(result.outputTokens == 25)
}

@Test("Floating usage token values are accepted when integral")
func floatingUsageTokensAreAccepted() throws {
  let body = #"{"model": "gpt-4", "usage": {"prompt_tokens": 10.0, "completion_tokens": 20.0}}"#
  let data = try #require(body.data(using: .utf8))
  let result = try #require(AIResponseParser.parse(data: data))

  #expect(result.inputTokens == 10)
  #expect(result.outputTokens == 20)
}

@Test("Ollama response format parses prompt_eval_count and eval_count")
func ollamaResponseParsing() throws {
  let body = #"{"model": "llama", "prompt_eval_count": 50, "eval_count": 100}"#
  let data = try #require(body.data(using: .utf8))
  let result = try #require(AIResponseParser.parse(data: data))

  #expect(result.model == "llama")
  #expect(result.inputTokens == 50)
  #expect(result.outputTokens == 100)
}

@Test("Response with no usage data returns nil")
func noUsageDataReturnsNil() throws {
  let body = #"{"choices": [{"text": "hello"}]}"#
  let data = try #require(body.data(using: .utf8))
  let result = AIResponseParser.parse(data: data)
  #expect(result == nil)
}

@Test("Invalid JSON response returns nil")
func invalidJSONResponseReturnsNil() throws {
  let body = "not valid json"
  let data = try #require(body.data(using: .utf8))
  let result = AIResponseParser.parse(data: data)
  #expect(result == nil)
}

@Test("Empty response body returns nil")
func emptyResponseBodyReturnsNil() throws {
  let result = AIResponseParser.parse(data: Data())
  #expect(result == nil)
}

@Test("Response with only model field is returned")
func responseWithOnlyModelField() throws {
  let body = #"{"model": "gpt-4"}"#
  let data = try #require(body.data(using: .utf8))
  let result = try #require(AIResponseParser.parse(data: data))

  #expect(result.model == "gpt-4")
  #expect(result.inputTokens == nil)
  #expect(result.outputTokens == nil)
}

@Test("Anthropic tokens override OpenAI tokens when both present in usage")
func anthropicTokensOverrideOpenAI() throws {
  let body = #"{"model": "m", "usage": {"prompt_tokens": 10, "completion_tokens": 20, "input_tokens": 15, "output_tokens": 25}}"#
  let data = try #require(body.data(using: .utf8))
  let result = try #require(AIResponseParser.parse(data: data))

  // Anthropic keys take precedence over OpenAI keys per parser logic
  #expect(result.inputTokens == 15)
  #expect(result.outputTokens == 25)
}
