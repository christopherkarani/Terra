import Foundation

extension Terra {
  /// Severity level for a Terra diagnostic issue.
  public enum Severity: String, Sendable, Hashable {
    case error
    case warning
    case info
  }

  /// A single Terra setup or workflow issue discovered by `diagnose()`.
  ///
  /// Each issue includes a stable code and a concrete fix so agents and humans
  /// can move directly from diagnosis to a corrected integration.
  public struct Issue: Sendable, Hashable {
    public let code: String
    public let severity: Severity
    public let explanation: String
    public let fix: String

    public init(code: String, severity: Severity, explanation: String, fix: String) {
      self.code = code
      self.severity = severity
      self.explanation = explanation
      self.fix = fix
    }
  }

  /// Validation output for Terra setup and active tracing context.
  ///
  /// Use this during development to catch common setup gaps before debugging
  /// the wrong layer of a GenAI workflow.
  public struct DiagnosticReport: Sendable, Hashable {
    public let issues: [Issue]
    public let suggestions: [String]
    public let isHealthy: Bool

    public init(issues: [Issue], suggestions: [String], isHealthy: Bool) {
      self.issues = issues
      self.suggestions = suggestions
      self.isHealthy = isHealthy
    }
  }

  /// Validates the current Terra setup and explains any problems it finds.
  ///
  /// `diagnose()` is synchronous and local-only. It does not emit network traffic.
  /// The report is intentionally opinionated so coding agents can choose the next
  /// Terra action without inspecting internal source files.
  ///
  /// ```swift
  /// let report = Terra.diagnose()
  /// if !report.isHealthy {
  ///   print(report.suggestions.joined(separator: "\n"))
  /// }
  /// ```
  public static func diagnose() -> DiagnosticReport {
    var issues: [Issue] = []
    var suggestions: [String] = []
    let hasProvider = _hasInstalledOpenTelemetryProviders || Runtime.shared.tracerProvider != nil || Runtime.shared.loggerProvider != nil

    if let configuration = _installedOpenTelemetryConfiguration {
      if configuration.otlpTracesEndpoint.absoluteString.isEmpty {
        issues.append(
          Issue(
            code: "MISSING_ENDPOINT",
            severity: .error,
            explanation: "Terra has an installed OpenTelemetry configuration but no traces endpoint was resolved.",
            fix: "Set a valid OTLP traces endpoint or call Terra.quickStart() for local development. Hint: print(Terra.help())."
          )
        )
      }
    } else {
      issues.append(
        Issue(
          code: "MISSING_ENDPOINT",
          severity: hasProvider ? .warning : .error,
          explanation: "No OTLP endpoint is configured for Terra's managed exporter path.",
          fix: "Call Terra.quickStart() for localhost development, or start Terra with a configuration that resolves an OTLP endpoint. Hint: print(Terra.help())."
        )
      )
      suggestions.append("If you are using an injected test tracer, this warning can be ignored for unit tests.")
    }

    let privacy = Runtime.shared.privacy
    if privacy == .default {
      issues.append(
        Issue(
          code: "MISSING_PRIVACY_POLICY",
          severity: .warning,
          explanation: "Terra is still using the default internal privacy policy.",
          fix: "Call Terra.start(...) or install Terra with an explicit privacy policy before validating production behavior. Hint: use Terra.ask(\"privacy include content\")."
        )
      )
    }

    if !hasProvider {
      issues.append(
        Issue(
          code: "NO_PROVIDER",
          severity: .error,
          explanation: "Terra does not currently have a tracer, meter, or logger provider installed.",
          fix: "Call Terra.quickStart(), Terra.start(...), or Terra.install(...) with providers before tracing work. Hint: print(Terra.help()) and rerun Terra.diagnose()."
        )
      )
    }

    if !_hasSwiftTaskContext() {
      issues.append(
        Issue(
          code: "NO_SWIFT_TASK_CONTEXT",
          severity: .info,
          explanation: "diagnose() is running outside a Swift task, so it cannot verify task-local span propagation.",
          fix: "Run Terra.diagnose() inside an async workflow or inside Terra.trace(...) when validating propagation. Hint: inspect Terra.examples() for the nearest runnable setup."
        )
      )
    }

    if _hasSwiftTaskContext(), currentSpan() == nil {
      suggestions.append("If you expected an active span here, wrap the enclosing async workflow in Terra.trace(name:id:_:) or inspect Terra.activeSpans().")
    }

    if _hasSwiftTaskContext(), currentSpan() != nil {
      suggestions.append("An active Terra span is visible in the current async context.")
    }

    suggestions.append("Hint: print(Terra.help()) for the canonical entry-point map.")
    suggestions.append(#"Hint: use Terra.ask("agent loop") or Terra.ask("quickstart and diagnose setup") for targeted guidance."#)
    suggestions.append("Hint: inspect Terra.examples() for runnable patterns and Terra.guides() for copy-paste explanations.")

    if issues.isEmpty {
      suggestions.append("Terra is healthy for local tracing. Use Terra.examples() for the closest runnable pattern.")
    }

    let isHealthy = !issues.contains { $0.severity == .error }
    return DiagnosticReport(issues: issues, suggestions: suggestions, isHealthy: isHealthy)
  }
}
