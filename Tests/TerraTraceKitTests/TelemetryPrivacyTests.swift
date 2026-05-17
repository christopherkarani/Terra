import Foundation
@testable import TerraTraceKit
import Testing

/// Privacy-redaction guarantees that have to hold even when the schema can't be
/// loaded (CLI tools, embedded frameworks where Bundle.module is missing, etc).
@Suite("TelemetryPrivacy fallback + audit-flag", .serialized)
struct TelemetryPrivacyFallbackTests {
  // MARK: P0-1 — audit signal must survive redaction

  @Test("Audit flag terra.redaction.applied is not redacted in fallback set")
  func testTelemetryPrivacyDoesNotRedactAuditFlagAttribute() throws {
    let displayed = TelemetryPrivacy.displayValue(
      forKey: "terra.redaction.applied",
      value: "true"
    )
    #expect(displayed == "true")
    #expect(displayed != TelemetryPrivacy.redactedValue)

    // The fallback list must NOT contain the audit flag — even if the schema
    // is unavailable at runtime, this boolean must survive.
    #expect(!TelemetryPrivacy.fallbackSensitiveAttributeKeys.contains("terra.redaction.applied"))
  }

  @Test("Schema-driven sensitive-keys parser excludes privacy_audit_detail entries")
  func testSchemaParserExcludesAuditFlagBehavior() throws {
    let schema = """
    {
      "registry": [
        {
          "key": "audit.flag",
          "viewer_behavior": "privacy_audit_detail"
        },
        {
          "key": "secret.payload",
          "viewer_behavior": "privacy_sensitive_detail"
        },
        {
          "key": "ordinary.detail",
          "viewer_behavior": "span_detail"
        }
      ]
    }
    """
    let keys = try #require(TelemetryPrivacy.sensitiveKeys(fromSchemaData: Data(schema.utf8)))

    #expect(keys.contains("secret.payload"))
    #expect(!keys.contains("audit.flag"))
    #expect(!keys.contains("ordinary.detail"))
  }

  // MARK: P0-2 — schema discovery from Bundle.module + fallback completeness

  @Test("Schema parser resolves the audit-flagged keys when fed the shipped schema")
  func testTelemetryPrivacyResolvesSchemaFromBundleModule() throws {
    // The schema must be discoverable from the repository checkout — the
    // shipped framework copy is wired via the `resources:` stanza in
    // Package.swift so runtime callers find it under Bundle(for:).
    let schemaURL = try locateRepositorySchema()
    let data = try Data(contentsOf: schemaURL)
    let keys = try #require(TelemetryPrivacy.sensitiveKeys(fromSchemaData: data))

    #expect(keys.contains("gen_ai.prompt.content"))
    #expect(keys.contains("terra.fm.tool.arguments"))
    #expect(keys.contains("terra.service.input_length"))
    // Audit signal must NOT appear in the schema-driven sensitive set.
    #expect(!keys.contains("terra.redaction.applied"))
  }

  @Test("displayValue redacts schema-driven sensitive keys")
  func testTelemetryPrivacyUsesResolvedKeys() throws {
    // Whichever discovery path wins (bundle resource or cwd walk),
    // `displayValue` must redact known privacy-sensitive content keys.
    #expect(
      TelemetryPrivacy.displayValue(
        forKey: "gen_ai.prompt.content",
        value: "user supplied prompt"
      ) == TelemetryPrivacy.redactedValue
    )
    #expect(
      TelemetryPrivacy.displayValue(
        forKey: "terra.service.input_length",
        value: "128"
      ) == TelemetryPrivacy.redactedValue
    )
    #expect(
      TelemetryPrivacy.displayValue(
        forKey: "terra.fm.tool.name",
        value: "search"
      ) == TelemetryPrivacy.redactedValue
    )
    #expect(
      TelemetryPrivacy.displayValue(
        forKey: "exception.message",
        value: "raw model prompt leaked through an error"
      ) == TelemetryPrivacy.redactedValue
    )
    #expect(
      TelemetryPrivacy.displayValue(
        forKey: "http.url",
        value: "https://provider.example/v1?key=secret"
      ) == TelemetryPrivacy.redactedValue
    )
  }

  @Test("Schema URL absent: parser returns nil and caller can fall back")
  func testTelemetryPrivacyFallsBackWhenSchemaURLAbsent() throws {
    // Empty / malformed JSON returns nil — caller must use fallback set.
    let empty = Data("{}".utf8)
    #expect(TelemetryPrivacy.sensitiveKeys(fromSchemaData: empty) == nil)

    let invalid = Data("{not json".utf8)
    #expect(TelemetryPrivacy.sensitiveKeys(fromSchemaData: invalid) == nil)

    // A schema with only non-sensitive entries also returns nil so that the
    // discovery loop continues searching candidate URLs.
    let nonSensitive = """
    {"registry": [{"key": "foo", "viewer_behavior": "span_detail"}]}
    """
    #expect(TelemetryPrivacy.sensitiveKeys(fromSchemaData: Data(nonSensitive.utf8)) == nil)
  }

  @Test("Fallback set covers every privacy-sensitive key flagged by the audit")
  func testTelemetryPrivacyFallbackContainsAllPrivacySensitiveKeys() throws {
    let required: Set<String> = [
      // P0-1: audit signal must NOT appear here.
      // P0-2 audit-flagged additions:
      "terra.service.input_length",
      "terra.fm.tool.name",
      // Pre-existing sensitive content that must survive even if both lookups fail:
      "gen_ai.prompt.content",
      "terra.prompt.length",
      "terra.prompt.hmac_sha256",
      "terra.prompt.sha256",
      "terra.safety.subject.length",
      "terra.safety.subject.hmac_sha256",
      "terra.safety.subject.sha256",
      "terra.anonymization.key_id",
      "terra.fm.tool.arguments",
      "terra.fm.tool.result",
      "exception.message",
      "http.url",
      "url.full",
    ]

    let fallback = TelemetryPrivacy.fallbackSensitiveAttributeKeys
    for key in required {
      #expect(fallback.contains(key), "fallback missing required privacy-sensitive key: \(key)")
    }
    // Audit flag must NEVER be in the fallback set.
    #expect(!fallback.contains("terra.redaction.applied"))
  }
}

// MARK: - P1-5 — status description / event name / link redaction helpers

@Suite("TelemetryPrivacy content-bearing helpers", .serialized)
struct TelemetryPrivacyContentHelperTests {
  @Test("Status descriptions that look like content are redacted")
  func testStatusDescriptionContentBearingIsRedacted() {
    let sentence = "User asked the assistant to summarize their personal email."
    #expect(TelemetryPrivacy.shouldRedactStatusDescription(sentence))

    let punctuated = "Failed: prompt = 'list my private files'"
    #expect(TelemetryPrivacy.shouldRedactStatusDescription(punctuated))

    let multiword = "model returned partial output"
    #expect(TelemetryPrivacy.shouldRedactStatusDescription(multiword))
  }

  @Test("Short error codes are not redacted")
  func testStatusDescriptionShortCodeIsKept() {
    #expect(!TelemetryPrivacy.shouldRedactStatusDescription("ECONNRESET"))
    #expect(!TelemetryPrivacy.shouldRedactStatusDescription("E_TIMEOUT"))
    #expect(!TelemetryPrivacy.shouldRedactStatusDescription("HTTP_500"))
    #expect(!TelemetryPrivacy.shouldRedactStatusDescription(""))
  }

  @Test("Known Terra event names are not redacted")
  func testKnownEventNamesAreKept() {
    #expect(!TelemetryPrivacy.shouldRedactEventName("terra.first_token"))
    #expect(!TelemetryPrivacy.shouldRedactEventName("chunk.stream"))
    #expect(!TelemetryPrivacy.shouldRedactEventName("terra.parent.explicit_ended"))
    #expect(!TelemetryPrivacy.shouldRedactEventName("terra.recommendation"))
    #expect(!TelemetryPrivacy.shouldRedactEventName("terra.anomaly.thermal"))
    #expect(!TelemetryPrivacy.shouldRedactEventName("terra.policy.violation"))
  }

  @Test("Unknown / user-supplied event names are redacted")
  func testUnknownEventNamesAreRedacted() {
    #expect(TelemetryPrivacy.shouldRedactEventName("user wrote: hello model"))
    #expect(TelemetryPrivacy.shouldRedactEventName("custom.payload.with content"))
    #expect(TelemetryPrivacy.shouldRedactEventName("Summarize my private notes"))
  }
}

// MARK: - Test helpers

/// Locates `Docs/telemetry-schema.json` by walking up from the test file.
/// Mirrors the production cwd-walk fallback so the test exercises the same
/// surface used by CLI tools and embedded contexts.
private func locateRepositorySchema() throws -> URL {
  var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  let fileManager = FileManager.default

  while candidate.path != "/" {
    let url = candidate.appendingPathComponent("Docs/telemetry-schema.json")
    if fileManager.fileExists(atPath: url.path) {
      return url
    }
    candidate.deleteLastPathComponent()
  }

  throw NSError(
    domain: "TelemetryPrivacyFallbackTests",
    code: 1,
    userInfo: [NSLocalizedDescriptionKey: "Could not locate Docs/telemetry-schema.json from \(#filePath)"]
  )
}
