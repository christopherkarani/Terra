import Foundation
import Testing
@testable import TerraHTTPInstrument

@Suite("HTTPAIInstrumentation Host Matching", .serialized)
struct HTTPAIInstrumentationTests {
  private final class ConfigurationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var configuration: HTTPAIInstrumentation.Configuration

    init(_ configuration: HTTPAIInstrumentation.Configuration) {
      self.configuration = configuration
    }

    func load() -> HTTPAIInstrumentation.Configuration {
      lock.lock()
      let configuration = self.configuration
      lock.unlock()
      return configuration
    }

    func store(_ configuration: HTTPAIInstrumentation.Configuration) {
      lock.lock()
      self.configuration = configuration
      lock.unlock()
    }
  }

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

  @Test("Configuration closures can observe runtime host updates")
  func configurationClosuresObserveUpdates() {
    let box = ConfigurationBox(.init(
      hosts: ["one.example"],
      openClawGatewayHosts: [],
      openClawMode: "disabled"
    ))
    let config = HTTPAIInstrumentation.makeConfiguration(
      hosts: ["one.example"],
      openClawGatewayHosts: [],
      openClawMode: "disabled",
      configurationProvider: { box.load() }
    )

    let one = URLRequest(url: URL(string: "https://one.example/v1/chat/completions")!)
    let two = URLRequest(url: URL(string: "https://two.example/v1/chat/completions")!)

    #expect(config.shouldInstrument?(one) == true)
    #expect(config.shouldInstrument?(two) == false)

    box.store(.init(
      hosts: ["two.example"],
      openClawGatewayHosts: [],
      openClawMode: "disabled"
    ))

    #expect(config.shouldInstrument?(one) == false)
    #expect(config.shouldInstrument?(two) == true)
    #expect(config.nameSpan?(two) == "chat two.example")
  }
}
