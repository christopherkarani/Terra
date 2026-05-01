import Testing
import Foundation
@testable import TerraHTTPInstrument

// MARK: - Multi-Provider Parser Tests (P1-8)
//
// These tests cover provider-shape parity beyond the existing OpenAI/Anthropic
// happy paths: Gemini, Bedrock (Claude/Llama/Titan), Azure OpenAI, and Cohere.
// Models that live in the URL path (Gemini, Azure deployments, Bedrock model
// IDs) require URL-aware extraction — exercised here.

@Suite("AIRequestParser Multi-Provider", .serialized)
struct AIRequestParserMultiProviderTests {

  // MARK: Gemini

  @Test("Gemini request: extracts model from URL path and generationConfig fields")
  func testGeminiRequestParsing_extractsModelFromUrl_andGenerationConfig() throws {
    let body = #"""
    {
      "contents": [
        {"role": "user", "parts": [{"text": "Hello Gemini"}]}
      ],
      "generationConfig": {
        "temperature": 0.42,
        "maxOutputTokens": 256,
        "candidateCount": 1
      }
    }
    """#
    let data = try #require(body.data(using: .utf8))
    let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent")!

    let result = try #require(AIRequestParser.parse(body: data, url: url))

    #expect(result.model == "gemini-1.5-pro")
    #expect(result.maxTokens == 256)
    #expect(result.temperature == 0.42)
    #expect(result.messages.count == 1)
    #expect(result.messages[0].role == "user")
    #expect(result.messages[0].content == "Hello Gemini")
  }

  @Test("Gemini request: streamGenerateContent path yields stream=true")
  func testGeminiRequest_streamGenerateContentPath() throws {
    let body = #"""
    {
      "contents": [{"role": "user", "parts": [{"text": "Stream me"}]}],
      "generationConfig": {"maxOutputTokens": 32}
    }
    """#
    let data = try #require(body.data(using: .utf8))
    let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:streamGenerateContent")!

    let result = try #require(AIRequestParser.parse(body: data, url: url))

    #expect(result.model == "gemini-1.5-flash")
    #expect(result.stream == true)
  }

  // MARK: Bedrock

  @Test("Bedrock Anthropic-on-Bedrock: extracts model from URL path; messages parsed")
  func testBedrockClaudeRequestParsing_extractsModelFromUrl() throws {
    let body = #"""
    {
      "anthropic_version": "bedrock-2023-05-31",
      "max_tokens": 1024,
      "messages": [{"role": "user", "content": "hi"}]
    }
    """#
    let data = try #require(body.data(using: .utf8))
    let url = URL(string: "https://bedrock-runtime.us-east-1.amazonaws.com/model/anthropic.claude-3-sonnet-20240229-v1%3A0/invoke")!

    let result = try #require(AIRequestParser.parse(body: data, url: url))

    #expect(result.model == "anthropic.claude-3-sonnet-20240229-v1:0")
    #expect(result.maxTokens == 1024)
    #expect(result.messages.count == 1)
    #expect(result.messages[0].role == "user")
    #expect(result.messages[0].content == "hi")
  }

  @Test("Bedrock Llama-on-Bedrock: top-level prompt + max_gen_len")
  func testBedrockLlamaRequestParsing_topLevelPromptAndMaxGenLen() throws {
    let body = #"""
    {
      "prompt": "Tell me a joke",
      "max_gen_len": 128,
      "temperature": 0.5
    }
    """#
    let data = try #require(body.data(using: .utf8))
    let url = URL(string: "https://bedrock-runtime.us-west-2.amazonaws.com/model/meta.llama3-70b-instruct-v1%3A0/invoke")!

    let result = try #require(AIRequestParser.parse(body: data, url: url))

    #expect(result.model == "meta.llama3-70b-instruct-v1:0")
    #expect(result.maxTokens == 128)
    #expect(result.temperature == 0.5)
  }

  @Test("Bedrock Titan: inputText + textGenerationConfig")
  func testBedrockTitanRequestParsing_inputTextAndConfig() throws {
    let body = #"""
    {
      "inputText": "What is the capital of France?",
      "textGenerationConfig": {
        "maxTokenCount": 200,
        "temperature": 0.3
      }
    }
    """#
    let data = try #require(body.data(using: .utf8))
    let url = URL(string: "https://bedrock-runtime.us-east-1.amazonaws.com/model/amazon.titan-text-express-v1/invoke-with-response-stream")!

    let result = try #require(AIRequestParser.parse(body: data, url: url))

    #expect(result.model == "amazon.titan-text-express-v1")
    #expect(result.maxTokens == 200)
    #expect(result.temperature == 0.3)
    #expect(result.stream == true)
  }

  // MARK: Azure OpenAI

  @Test("Azure OpenAI: deployment name extracted from URL path when body lacks model")
  func testAzureOpenAIRequestModelFromURLPath() throws {
    let body = #"""
    {
      "messages": [{"role": "user", "content": "ping"}],
      "max_tokens": 64,
      "temperature": 0.2
    }
    """#
    let data = try #require(body.data(using: .utf8))
    let url = URL(string: "https://my-azure.openai.azure.com/openai/deployments/gpt4-prod/chat/completions?api-version=2024-02-15-preview")!

    let result = try #require(AIRequestParser.parse(body: data, url: url))

    #expect(result.model == "gpt4-prod")
    #expect(result.maxTokens == 64)
    #expect(result.temperature == 0.2)
    #expect(result.messages.count == 1)
  }
}

@Suite("AIResponseParser Multi-Provider", .serialized)
struct AIResponseParserMultiProviderTests {

  @Test("Gemini response: maps usageMetadata to input/output tokens")
  func testGeminiResponseParsing_mapsUsageMetadata() throws {
    let body = #"""
    {
      "modelVersion": "gemini-1.5-pro",
      "usageMetadata": {
        "promptTokenCount": 33,
        "candidatesTokenCount": 77,
        "totalTokenCount": 110
      }
    }
    """#
    let data = try #require(body.data(using: .utf8))
    let result = try #require(AIResponseParser.parse(data: data))

    #expect(result.inputTokens == 33)
    #expect(result.outputTokens == 77)
  }

  @Test("Bedrock Anthropic-on-Bedrock: camelCase usage tokens")
  func testBedrockClaudeResponseParsing_camelCaseUsage() throws {
    let body = #"""
    {
      "id": "msg_xyz",
      "usage": {
        "inputTokens": 21,
        "outputTokens": 42
      }
    }
    """#
    let data = try #require(body.data(using: .utf8))
    let result = try #require(AIResponseParser.parse(data: data))

    #expect(result.inputTokens == 21)
    #expect(result.outputTokens == 42)
  }

  @Test("Bedrock Titan: inputTextTokenCount + results[0].tokenCount")
  func testBedrockTitanResponseParsing_topLevelTokenCounts() throws {
    let body = #"""
    {
      "inputTextTokenCount": 12,
      "results": [
        {"tokenCount": 34, "outputText": "Paris"}
      ]
    }
    """#
    let data = try #require(body.data(using: .utf8))
    let result = try #require(AIResponseParser.parse(data: data))

    #expect(result.inputTokens == 12)
    #expect(result.outputTokens == 34)
  }

  @Test("Bedrock Llama: prompt_token_count + generation_token_count")
  func testBedrockLlamaResponseParsing_promptAndGenerationCounts() throws {
    let body = #"""
    {
      "generation": "...",
      "prompt_token_count": 7,
      "generation_token_count": 19,
      "stop_reason": "stop"
    }
    """#
    let data = try #require(body.data(using: .utf8))
    let result = try #require(AIResponseParser.parse(data: data))

    #expect(result.inputTokens == 7)
    #expect(result.outputTokens == 19)
  }

  @Test("Cohere response: maps meta.tokens.{input_tokens,output_tokens}")
  func testCohereResponseParsing_mapsMetaTokens() throws {
    let body = #"""
    {
      "id": "abc-123",
      "text": "hello",
      "meta": {
        "tokens": {
          "input_tokens": 11,
          "output_tokens": 22
        }
      }
    }
    """#
    let data = try #require(body.data(using: .utf8))
    let result = try #require(AIResponseParser.parse(data: data))

    #expect(result.inputTokens == 11)
    #expect(result.outputTokens == 22)
  }
}

@Suite("HTTPAIInstrumentation Default Hosts", .serialized)
struct HTTPAIInstrumentationDefaultHostsTests {

  @Test("Default hosts include Azure OpenAI subdomain match")
  func defaultHostsIncludeAzureOpenAI() {
    let hosts = HTTPAIInstrumentation.defaultAIHosts
    let azureMatched = hosts.contains { target in
      HTTPAIInstrumentation.isHostBoundaryMatch(host: "my-azure.openai.azure.com", target: target)
    }
    #expect(azureMatched, "openai.azure.com should match Azure OpenAI subdomains")
  }

  @Test("Default hosts include Bedrock regional runtime")
  func defaultHostsIncludeBedrock() {
    let hosts = HTTPAIInstrumentation.defaultAIHosts
    let bedrockMatched = hosts.contains { target in
      HTTPAIInstrumentation.isHostBoundaryMatch(host: "bedrock-runtime.us-east-1.amazonaws.com", target: target)
    }
    #expect(bedrockMatched, "Bedrock runtime hostnames should match")
  }

  @Test("Default hosts include DeepSeek, Grok, OpenRouter, Perplexity")
  func defaultHostsIncludeNewProviders() {
    let hosts = HTTPAIInstrumentation.defaultAIHosts

    #expect(hosts.contains { HTTPAIInstrumentation.isHostBoundaryMatch(host: "api.deepseek.com", target: $0) })
    #expect(hosts.contains { HTTPAIInstrumentation.isHostBoundaryMatch(host: "api.x.ai", target: $0) })
    #expect(hosts.contains { HTTPAIInstrumentation.isHostBoundaryMatch(host: "openrouter.ai", target: $0) })
    #expect(hosts.contains { HTTPAIInstrumentation.isHostBoundaryMatch(host: "api.perplexity.ai", target: $0) })
  }
}
