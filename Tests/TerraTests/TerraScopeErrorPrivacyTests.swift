import XCTest

@testable import TerraCore

final class TerraScopeErrorPrivacyTests: XCTestCase {
  private var support: TerraTestSupport!

  enum SecretError: Error, CustomStringConvertible {
    case leaked(String)

    var description: String {
      switch self {
      case .leaked(let value):
        return "sensitive:\(value)"
      }
    }
  }

  override func setUp() {
    super.setUp()
    support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))
  }

  override func tearDown() {
    support.reset()
    super.tearDown()
  }

  func testRecordError_defaultPrivacy_doesNotCaptureSensitiveMessage() async throws {
    let secret = "private-token"
    let request = Terra.InferenceRequest(model: "local/llama-3.2-1b")

    do {
      _ = try await Terra.withInferenceSpan(request) { _ in
        throw SecretError.leaked(secret)
      }
      XCTFail("Expected error")
    } catch {
      // Expected.
    }

    let span = try XCTUnwrap(support.finishedSpans().first)
    let exceptionEvent = try XCTUnwrap(span.events.first(where: { $0.name == "exception" }))

    XCTAssertNil(exceptionEvent.attributes["exception.message"])
    XCTAssertNil(exceptionEvent.attributes[Terra.Keys.Terra.errorMessageLength])
    XCTAssertNil(exceptionEvent.attributes[Terra.Keys.Terra.errorMessageHMACSHA256])
    XCTAssertNil(exceptionEvent.attributes[Terra.Keys.Terra.errorMessageSHA256])
    XCTAssertFalse(span.status.description.contains(secret))
  }

  func testRecordError_hmacRedaction_recordsLengthAndDigestWithoutRawMessage() async throws {
    Terra.install(
      .init(
        privacy: .init(contentPolicy: .always, redaction: .hashHMACSHA256),
        tracerProvider: support.tracerProvider,
        registerProvidersAsGlobal: false
      )
    )

    let secret = "private-token"
    let request = Terra.InferenceRequest(model: "local/llama-3.2-1b")

    do {
      _ = try await Terra.withInferenceSpan(request) { _ in
        throw SecretError.leaked(secret)
      }
      XCTFail("Expected error")
    } catch {
      // Expected.
    }

    let span = try XCTUnwrap(support.finishedSpans().first)
    let exceptionEvent = try XCTUnwrap(span.events.first(where: { $0.name == "exception" }))

    let expectedLength = SecretError.leaked(secret).description.count
    XCTAssertEqual(exceptionEvent.attributes[Terra.Keys.Terra.errorMessageLength]?.description, String(expectedLength))
    XCTAssertNil(exceptionEvent.attributes["exception.message"])
    XCTAssertFalse(exceptionEvent.attributes.values.contains { $0.description.contains(secret) })

    #if canImport(CryptoKit) || canImport(Crypto)
      let digest = exceptionEvent.attributes[Terra.Keys.Terra.errorMessageHMACSHA256]?.description
      XCTAssertEqual(digest?.count, 64)
      XCTAssertNotNil(exceptionEvent.attributes[Terra.Keys.Terra.anonymizationKeyID])
    #else
      XCTAssertNil(exceptionEvent.attributes[Terra.Keys.Terra.errorMessageHMACSHA256])
    #endif
  }
}
