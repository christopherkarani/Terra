extension Terra {
  /// Privacy validation mode for non-mutating Terra policy audits.
  public enum PrivacyAuditMode: String, Sendable, Hashable {
    /// Reports risky settings without enforcing the strictest no-content-derived-telemetry stance.
    case standard
    /// Treats content capture and content-derived telemetry as audit failures unless privacy is silent.
    case strict
  }

  /// Severity for privacy audit findings.
  public enum PrivacyAuditSeverity: String, Sendable, Hashable {
    case error
    case warning
    case info
  }

  /// Public privacy inputs that can be audited without installing or mutating Terra.
  public struct PrivacyAuditConfiguration: Sendable, Hashable {
    public let privacyPolicy: PrivacyPolicy
    public let defaultCapturePolicy: CapturePolicy
    public let capturesErrorMessages: Bool

    public init(
      privacyPolicy: PrivacyPolicy = .redacted,
      defaultCapturePolicy: CapturePolicy = .default,
      capturesErrorMessages: Bool = false
    ) {
      self.privacyPolicy = privacyPolicy
      self.defaultCapturePolicy = defaultCapturePolicy
      self.capturesErrorMessages = capturesErrorMessages
    }
  }

  /// A single privacy audit finding with a stable code and concrete remediation.
  public struct PrivacyAuditFinding: Sendable, Hashable {
    public let code: String
    public let severity: PrivacyAuditSeverity
    public let explanation: String
    public let fix: String

    public init(
      code: String,
      severity: PrivacyAuditSeverity,
      explanation: String,
      fix: String
    ) {
      self.code = code
      self.severity = severity
      self.explanation = explanation
      self.fix = fix
    }
  }

  /// Non-mutating validation result for Terra privacy and capture settings.
  public struct PrivacyAuditReport: Sendable, Hashable {
    public let mode: PrivacyAuditMode
    public let configuration: PrivacyAuditConfiguration
    public let findings: [PrivacyAuditFinding]
    public let recommendedFixes: [String]
    public let isCompliant: Bool

    public init(
      mode: PrivacyAuditMode,
      configuration: PrivacyAuditConfiguration,
      findings: [PrivacyAuditFinding],
      recommendedFixes: [String],
      isCompliant: Bool
    ) {
      self.mode = mode
      self.configuration = configuration
      self.findings = findings
      self.recommendedFixes = recommendedFixes
      self.isCompliant = isCompliant
    }
  }

  /// Audits a Terra privacy configuration without installing it or changing runtime capture behavior.
  public static func auditPrivacy(
    configuration: PrivacyAuditConfiguration,
    mode: PrivacyAuditMode = .strict
  ) -> PrivacyAuditReport {
    let findings = _privacyAuditFindings(configuration: configuration, mode: mode)
    return PrivacyAuditReport(
      mode: mode,
      configuration: configuration,
      findings: findings,
      recommendedFixes: findings.map(\.fix),
      isCompliant: !findings.contains { $0.severity == .error }
    )
  }

  /// Audits a Terra privacy policy and default capture policy without mutating runtime state.
  public static func auditPrivacy(
    privacyPolicy: PrivacyPolicy,
    capturePolicy: CapturePolicy = .default,
    mode: PrivacyAuditMode = .strict
  ) -> PrivacyAuditReport {
    auditPrivacy(
      configuration: PrivacyAuditConfiguration(
        privacyPolicy: privacyPolicy,
        defaultCapturePolicy: capturePolicy
      ),
      mode: mode
    )
  }

  /// Audits a single capture policy under a privacy policy without mutating runtime state.
  public static func auditCapturePolicy(
    _ capturePolicy: CapturePolicy,
    under privacyPolicy: PrivacyPolicy = .redacted,
    mode: PrivacyAuditMode = .strict
  ) -> PrivacyAuditReport {
    auditPrivacy(
      privacyPolicy: privacyPolicy,
      capturePolicy: capturePolicy,
      mode: mode
    )
  }

  /// Compatibility spelling for callers that prefer validation terminology.
  public static func validatePrivacyAudit(
    configuration: PrivacyAuditConfiguration,
    mode: PrivacyAuditMode = .strict
  ) -> PrivacyAuditReport {
    auditPrivacy(configuration: configuration, mode: mode)
  }

  /// Compatibility spelling for callers that prefer validation terminology.
  public static func validateCapturePolicy(
    _ capturePolicy: CapturePolicy,
    under privacyPolicy: PrivacyPolicy = .redacted,
    mode: PrivacyAuditMode = .strict
  ) -> PrivacyAuditReport {
    auditCapturePolicy(capturePolicy, under: privacyPolicy, mode: mode)
  }

  private static func _privacyAuditFindings(
    configuration: PrivacyAuditConfiguration,
    mode: PrivacyAuditMode
  ) -> [PrivacyAuditFinding] {
    var findings: [PrivacyAuditFinding] = []

    if configuration.privacyPolicy == .capturing {
      findings.append(PrivacyAuditFinding(
        code: mode == .strict ? "STRICT_PRIVACY_CAPTURES_BY_DEFAULT" : "PRIVACY_CAPTURES_BY_DEFAULT",
        severity: mode == .strict ? .error : .warning,
        explanation: "The capturing privacy policy permits content-derived telemetry without a per-call opt-in.",
        fix: "Use .redacted, .lengthOnly, or .silent for audited builds; reserve .capturing for controlled debugging."
      ))
    }

    if configuration.defaultCapturePolicy == .includeContent {
      if configuration.privacyPolicy == .silent {
        findings.append(PrivacyAuditFinding(
          code: "STRICT_PRIVACY_SILENT_OVERRIDES_CAPTURE",
          severity: .info,
          explanation: "The capture policy asks to include content, but .silent privacy prevents content capture.",
          fix: "No runtime change is required; consider removing .includeContent to make intent clearer."
        ))
      } else {
        findings.append(PrivacyAuditFinding(
          code: mode == .strict ? "STRICT_PRIVACY_INCLUDE_CONTENT" : "PRIVACY_INCLUDE_CONTENT",
          severity: mode == .strict ? .error : .warning,
          explanation: "The capture policy opts this configuration into content-derived telemetry.",
          fix: "Use .default capture policy for audited paths, or switch privacy to .silent when no content-derived signal is allowed."
        ))
      }
    }

    if configuration.privacyPolicy == .lengthOnly {
      findings.append(PrivacyAuditFinding(
        code: "PRIVACY_LENGTH_ONLY_DISCLOSURE",
        severity: .warning,
        explanation: "Length-only telemetry can still reveal approximate prompt or subject size when content capture is enabled.",
        fix: "Use .silent for the strictest audited flows, or keep capture policy at .default so content-derived length signals are not emitted."
      ))
    }

    if configuration.capturesErrorMessages && configuration.privacyPolicy != .silent {
      findings.append(PrivacyAuditFinding(
        code: mode == .strict ? "STRICT_PRIVACY_ERROR_MESSAGES" : "PRIVACY_ERROR_MESSAGES",
        severity: mode == .strict ? .error : .warning,
        explanation: "Error messages may contain user or model content and are not safe for strict audit capture.",
        fix: "Record exception type and status only, or use .silent privacy for audited execution paths."
      ))
    }

    if findings.isEmpty {
      findings.append(PrivacyAuditFinding(
        code: "PRIVACY_AUDIT_OK",
        severity: .info,
        explanation: "The audited privacy and capture settings do not permit content capture under the selected audit mode.",
        fix: "No privacy change is required for this audit mode."
      ))
    }

    return findings
  }
}
