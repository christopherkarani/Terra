import Foundation
import Testing
@testable import TerraHTTPInstrument

@Suite("HTTPAIInstrumentation Host Matching")
struct HTTPAIInstrumentationTests {
  @Test("Host boundary match allows exact host and subdomains")
  func hostBoundaryAllowsExactAndSubdomain() {
    #expect(HTTPAIInstrumentation.isHostBoundaryMatch(host: "api.openai.com", target: "api.openai.com"))
    #expect(HTTPAIInstrumentation.isHostBoundaryMatch(host: "foo.api.openai.com", target: "api.openai.com"))
  }

  @Test("Host boundary match rejects suffix confusion")
  func hostBoundaryRejectsSuffixConfusion() {
    #expect(!HTTPAIInstrumentation.isHostBoundaryMatch(host: "evilapi.openai.com", target: "api.openai.com"))
    #expect(!HTTPAIInstrumentation.isHostBoundaryMatch(host: "evil-ai.com", target: "ai.com"))
  }

  @Test("Host boundary match is case-insensitive")
  func hostBoundaryIsCaseInsensitive() {
    #expect(HTTPAIInstrumentation.isHostBoundaryMatch(host: "API.OPENAI.COM", target: "api.openai.com"))
  }

  @Test("Operation name infers embeddings and chat paths")
  func operationNameInference() {
    var embeddings = URLRequest(url: URL(string: "https://api.openai.com/v1/embeddings")!)
    embeddings.httpMethod = "POST"
    #expect(HTTPAIInstrumentation.operationName(for: embeddings) == "embeddings")

    var chat = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
    chat.httpMethod = "POST"
    #expect(HTTPAIInstrumentation.operationName(for: chat) == "chat")

    var unknown = URLRequest(url: URL(string: "https://api.openai.com/v1/images")!)
    unknown.httpMethod = "POST"
    #expect(HTTPAIInstrumentation.operationName(for: unknown) == "inference")
  }

  @Test("Install updates host matching configuration")
  func installUpdatesHostConfiguration() {
    HTTPAIInstrumentation.resetForTesting()
    defer { HTTPAIInstrumentation.resetForTesting() }

    HTTPAIInstrumentation.install(hosts: ["first.ai"])

    let firstRequest = URLRequest(url: URL(string: "https://first.ai/v1/chat/completions")!)
    let secondRequest = URLRequest(url: URL(string: "https://second.ai/v1/chat/completions")!)
    #expect(HTTPAIInstrumentation.shouldInstrument(firstRequest))
    #expect(!HTTPAIInstrumentation.shouldInstrument(secondRequest))

    HTTPAIInstrumentation.install(hosts: ["second.ai"])
    #expect(!HTTPAIInstrumentation.shouldInstrument(firstRequest))
    #expect(HTTPAIInstrumentation.shouldInstrument(secondRequest))
  }
}
