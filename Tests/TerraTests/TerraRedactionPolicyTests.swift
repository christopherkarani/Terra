import XCTest

@testable import TerraCore

final class TerraRedactionPolicyTests: XCTestCase {
  private var support: TerraTestSupport!

  override func setUp() {
    super.setUp()
    support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))
  }

  override func tearDown() {
    support.reset()
    super.tearDown()
  }

  func testDefaultPrivacy_doesNotRecordPromptAttributes() async throws {
    let secretPrompt = "my super secret"
    let request = Terra.InferenceRequest(model: "local/llama-3.2-1b", prompt: secretPrompt)

    await Terra.withInferenceSpan(request) { _ in }

    let span = try XCTUnwrap(support.finishedSpans().first)

    XCTAssertNil(span.attributes[Terra.Keys.Terra.promptLength])
    XCTAssertNil(span.attributes[Terra.Keys.Terra.promptHMACSHA256])
    XCTAssertNil(span.attributes[Terra.Keys.Terra.promptSHA256])

    // Ensure the raw prompt is not present in any attribute value.
    XCTAssertFalse(span.attributes.values.contains { $0.description.contains(secretPrompt) })
  }

  func testLengthOnlyRedaction_recordsLength_withoutRawPrompt() async throws {
    Terra.install(
      .init(privacy: .init(contentPolicy: .always, redaction: .lengthOnly))
    )

    let prompt = "hello"
    let request = Terra.InferenceRequest(model: "local/llama-3.2-1b", prompt: prompt)

    await Terra.withInferenceSpan(request) { _ in }

    let span = try XCTUnwrap(support.finishedSpans().first)
    XCTAssertEqual(span.attributes[Terra.Keys.Terra.promptLength]?.description, "5")
    XCTAssertNil(span.attributes[Terra.Keys.Terra.promptHMACSHA256])
    XCTAssertNil(span.attributes[Terra.Keys.Terra.promptSHA256])
    XCTAssertFalse(span.attributes.values.contains { $0.description.contains(prompt) })
  }

  func testDropRedaction_omitsPromptAttributes_withoutRawPrompt() async throws {
    Terra.install(
      .init(privacy: .init(contentPolicy: .always, redaction: .drop))
    )

    let prompt = "secret-prompt"
    let request = Terra.InferenceRequest(model: "local/llama-3.2-1b", prompt: prompt)

    await Terra.withInferenceSpan(request) { _ in }

    let span = try XCTUnwrap(support.finishedSpans().first)
    XCTAssertNil(span.attributes[Terra.Keys.Terra.promptLength])
    XCTAssertNil(span.attributes[Terra.Keys.Terra.promptHMACSHA256])
    XCTAssertNil(span.attributes[Terra.Keys.Terra.promptSHA256])
    XCTAssertFalse(span.attributes.values.contains { $0.description.contains(prompt) })
  }

  func testHMACRedaction_recordsHMACAndLength_withoutRawPrompt() async throws {
    Terra.install(
      .init(privacy: .init(contentPolicy: .always, redaction: .hashHMACSHA256))
    )

    let prompt = "hello"
    let request = Terra.InferenceRequest(model: "local/llama-3.2-1b", prompt: prompt)

    await Terra.withInferenceSpan(request) { _ in }

    let span = try XCTUnwrap(support.finishedSpans().first)
    XCTAssertEqual(span.attributes[Terra.Keys.Terra.promptLength]?.description, "5")

    let hmac = span.attributes[Terra.Keys.Terra.promptHMACSHA256]?.description
    XCTAssertNotNil(hmac)
    XCTAssertFalse(hmac?.contains(prompt) ?? true)
    XCTAssertEqual(hmac?.count, 64)

    XCTAssertNil(span.attributes[Terra.Keys.Terra.promptSHA256])
    XCTAssertNotNil(span.attributes[Terra.Keys.Terra.anonymizationKeyID])
  }

  func testHMACRedaction_canEnableLegacySHAAttributes() async throws {
    Terra.install(
      .init(
        privacy: .init(
          contentPolicy: .always,
          redaction: .hashHMACSHA256,
          emitLegacySHA256Attributes: true
        )
      )
    )

    let request = Terra.InferenceRequest(model: "local/llama-3.2-1b", prompt: "hello")
    await Terra.withInferenceSpan(request) { _ in }

    let span = try XCTUnwrap(support.finishedSpans().first)
    XCTAssertNotNil(span.attributes[Terra.Keys.Terra.promptHMACSHA256])
    XCTAssertNotNil(span.attributes[Terra.Keys.Terra.promptSHA256])
  }

  func testHMACRedactionLabel_matchesAvailability() async throws {
    Terra.install(
      .init(privacy: .init(contentPolicy: .always, redaction: .hashHMACSHA256))
    )

    support.tracerProvider.addSpanProcessor(TerraSpanEnrichmentProcessor())

    let request = Terra.InferenceRequest(model: "local/llama-3.2-1b", prompt: "hello")
    await Terra.withInferenceSpan(request) { _ in }

    let span = try XCTUnwrap(support.finishedSpans().first)
    let label = span.attributes[Terra.Keys.Terra.contentRedaction]?.description

    #if canImport(CryptoKit) || canImport(Crypto)
      XCTAssertEqual(label, "hash_hmac_sha256")
      let hmac = span.attributes[Terra.Keys.Terra.promptHMACSHA256]?.description
      XCTAssertEqual(hmac?.count, 64)
    #else
      XCTAssertEqual(label, "hash_unavailable")
      XCTAssertNil(span.attributes[Terra.Keys.Terra.promptHMACSHA256])
      XCTAssertNil(span.attributes[Terra.Keys.Terra.promptSHA256])
    #endif
  }

  func testLegacySHA256RedactionLabel_matchesAvailability() async throws {
    Terra.install(
      .init(privacy: .init(contentPolicy: .always, redaction: .hashSHA256))
    )

    support.tracerProvider.addSpanProcessor(TerraSpanEnrichmentProcessor())

    let request = Terra.InferenceRequest(model: "local/llama-3.2-1b", prompt: "hello")
    await Terra.withInferenceSpan(request) { _ in }

    let span = try XCTUnwrap(support.finishedSpans().first)
    let label = span.attributes[Terra.Keys.Terra.contentRedaction]?.description

    #if canImport(CryptoKit) || canImport(Crypto)
      XCTAssertEqual(label, "hash_sha256")
      let hash = span.attributes[Terra.Keys.Terra.promptSHA256]?.description
      XCTAssertEqual(hash?.count, 64)
    #else
      XCTAssertEqual(label, "hash_unavailable")
      XCTAssertNil(span.attributes[Terra.Keys.Terra.promptSHA256])
    #endif
  }

  func testHMACDigest_changesAcrossDifferentKeys() {
    let input = "hello"
    let keyA = Data("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".utf8)
    let keyB = Data("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".utf8)

    #if canImport(CryptoKit) || canImport(Crypto)
      let digestA = Runtime.hmacSHA256Hex(input, key: keyA)
      let digestB = Runtime.hmacSHA256Hex(input, key: keyB)
      XCTAssertNotNil(digestA)
      XCTAssertNotNil(digestB)
      XCTAssertNotEqual(digestA, digestB)
    #else
      XCTAssertNil(Runtime.hmacSHA256Hex(input, key: keyA))
      XCTAssertNil(Runtime.hmacSHA256Hex(input, key: keyB))
    #endif
  }

  func testSha256Hex_matchesExpectedOutput_orRequiresSha256LengthFallback() {
    let input = "hello"
    #if canImport(CryptoKit) || canImport(Crypto)
      XCTAssertEqual(
        Runtime.sha256Hex(input),
        "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
      )
    #else
      XCTAssertNil(Runtime.sha256Hex(input))
    #endif
  }
}
