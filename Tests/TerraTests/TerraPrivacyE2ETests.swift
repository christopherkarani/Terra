import XCTest

@testable import Terra

final class TerraPrivacyE2ETests: XCTestCase {
  private var support: TerraTestSupport!

  override func setUp() {
    super.setUp()
    support = TerraTestSupport()
    Terra.install(.init())
  }

  override func tearDown() {
    support.reset()
    super.tearDown()
  }

  /// Verifies that default privacy policy ensures raw prompt never appears in span attributes.
  func testDefaultPrivacy_exportedSpan_containsNoRawPrompt() async throws {
    let secretPrompt = "top-secret-prompt-content-xyz"
    let request = Terra.InferenceRequest(model: "local/test-model", prompt: secretPrompt)
    await Terra.withInferenceSpan(request) { _ in }

    let spans = support.finishedSpans()
    XCTAssertFalse(spans.isEmpty, "Expected at least one span to be recorded")

    for span in spans {
      for (key, value) in span.attributes {
        XCTAssertFalse(
          value.description.contains(secretPrompt),
          "Raw prompt found in span attribute '\(key)': \(value.description)"
        )
      }
      XCTAssertFalse(span.name.contains(secretPrompt), "Raw prompt found in span name")
    }
  }

  /// Verifies that lengthOnly redaction exports length but not raw prompt.
  func testLengthOnlyPrivacy_exportedSpan_containsLengthNotPrompt() async throws {
    Terra.install(.init(privacy: .init(contentPolicy: .always, redaction: .lengthOnly)))

    let secretPrompt = "top-secret-prompt-content-xyz"
    let request = Terra.InferenceRequest(model: "local/test-model", prompt: secretPrompt)
    await Terra.withInferenceSpan(request) { _ in }

    let spans = support.finishedSpans()
    XCTAssertFalse(spans.isEmpty, "Expected at least one span to be recorded")

    for span in spans {
      for (key, value) in span.attributes {
        XCTAssertFalse(
          value.description.contains(secretPrompt),
          "Raw prompt found in span attribute '\(key)': \(value.description)"
        )
      }
    }

    // Should have prompt_length attribute
    let span = try XCTUnwrap(spans.first)
    XCTAssertNotNil(
      span.attributes[Terra.Keys.Terra.promptLength],
      "Expected promptLength attribute with lengthOnly redaction"
    )
  }
}
