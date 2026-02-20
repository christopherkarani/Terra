import XCTest
import TerraLlama
@testable import TerraCore

final class TerraLlamaRuntimeTests: XCTestCase {
  private var support: TerraTestSupport!

  override func setUp() {
    super.setUp()
    support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))
  }

  override func tearDown() {
    support.reset()
    support = nil
    super.tearDown()
  }

  func testLlamaRuntimeUsesCanonicalContractValue() async throws {
    let requestModel = "test-llama.cpp-model"

    await TerraLlama.traced(model: requestModel) { _ in
      // streaming body intentionally empty; runtime contract should be set on span creation.
    }

    let spans = support.finishedSpans()
    let root = try XCTUnwrap(spans.first)
    XCTAssertEqual(
      root.attributes[Terra.Keys.Terra.runtime]?.description,
      Terra.RuntimeKind.llamaCpp.rawValue
    )
  }
}
