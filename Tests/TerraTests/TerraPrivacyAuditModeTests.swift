import Testing
import TerraCore

@Suite("Terra Privacy Audit Mode")
struct TerraPrivacyAuditModeTests {
  @Test("strict audit rejects capturing privacy policy")
  func strictAuditRejectsCapturingPrivacyPolicy() {
    let report = Terra.auditPrivacy(
      privacyPolicy: .capturing,
      capturePolicy: .default,
      mode: .strict
    )

    #expect(!report.isCompliant)
    #expect(report.findings.contains { $0.code == "STRICT_PRIVACY_CAPTURES_BY_DEFAULT" && $0.severity == .error })
  }

  @Test("strict audit rejects includeContent under redacted policy")
  func strictAuditRejectsIncludeContentUnderRedactedPolicy() {
    let report = Terra.auditCapturePolicy(.includeContent, under: .redacted, mode: .strict)

    #expect(!report.isCompliant)
    #expect(report.findings.contains { $0.code == "STRICT_PRIVACY_INCLUDE_CONTENT" && $0.severity == .error })
  }

  @Test("strict audit allows silent policy even when capture policy is includeContent")
  func strictAuditAllowsSilentPolicy() {
    let report = Terra.auditPrivacy(
      configuration: .init(privacyPolicy: .silent, defaultCapturePolicy: .includeContent),
      mode: .strict
    )

    #expect(report.isCompliant)
    #expect(report.findings.contains { $0.code == "STRICT_PRIVACY_SILENT_OVERRIDES_CAPTURE" && $0.severity == .info })
  }
}
