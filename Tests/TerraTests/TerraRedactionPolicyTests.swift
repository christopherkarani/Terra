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
    XCTAssertNil(span.attributes[Terra.Keys.Terra.promptSHA256])
    XCTAssertFalse(span.attributes.values.contains { $0.description.contains(prompt) })
  }

  func testHashRedaction_recordsHashAndLength_withoutRawPrompt() async throws {
    Terra.install(
      .init(privacy: .init(contentPolicy: .always, redaction: .hashSHA256))
    )

    let prompt = "hello"
    let request = Terra.InferenceRequest(model: "local/llama-3.2-1b", prompt: prompt)

    await Terra.withInferenceSpan(request) { _ in }

    let span = try XCTUnwrap(support.finishedSpans().first)
    XCTAssertEqual(span.attributes[Terra.Keys.Terra.promptLength]?.description, "5")

    let hash = span.attributes[Terra.Keys.Terra.promptSHA256]?.description
    XCTAssertNotNil(hash)
    XCTAssertFalse(hash?.contains(prompt) ?? true)
  }

  func testHashRedaction_isDeterministicWithRotationWindow() async throws {
    let policy = Terra.AnonymizationPolicy(
      enabled: true,
      keyID: "rotation-test",
      secret: "rotation-secret",
      rotationIntervalSeconds: 60
    )
    Terra.install(
      .init(
        privacy: .init(
          contentPolicy: .always,
          redaction: .hashSHA256,
          anonymizationPolicy: policy
        ),
        tracerProvider: support.tracerProvider
      )
    )

    let requestA = Terra.InferenceRequest(model: "local/llama-3.2-1b", prompt: "hello")
    await Terra.withInferenceSpan(requestA) { _ in }
    let firstHashA = support.finishedSpans().first?
      .attributes[Terra.Keys.Terra.promptSHA256]?.description

    support.reset()
    support.tracerProvider.forceFlush()

    let requestB = Terra.InferenceRequest(model: "local/llama-3.2-1b", prompt: "hello")
    await Terra.withInferenceSpan(requestB) { _ in }
    let firstHashB = support.finishedSpans().first?
      .attributes[Terra.Keys.Terra.promptSHA256]?.description

    XCTAssertNotNil(firstHashA)
    XCTAssertEqual(firstHashA, firstHashB)

    let policyBefore = Runtime.shared.privacy.anonymizationPolicy
    let now = Date(timeIntervalSince1970: 1000)
    let sameWindowA = policyBefore.keyID(for: now)
    let sameWindowB = policyBefore.keyID(for: now + 10)
    let nextWindow = policyBefore.keyID(for: now + 70)

    XCTAssertEqual(sameWindowA, sameWindowB)
    XCTAssertNotEqual(sameWindowA, nextWindow)
  }

  func testHashRedactionLabel_matchesAvailability() async throws {
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
