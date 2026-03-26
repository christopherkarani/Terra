import Testing
@testable import TerraCore

@Suite("TerraError remediation", .serialized)
struct TerraErrorRemediationTests {
  @Test("Known lifecycle TerraError codes provide deterministic remediation hints")
  func knownLifecycleErrorHints() {
    #expect(
      Terra.TerraError(code: .invalid_endpoint, message: "x").remediationHint
        == "Use a valid OTLP endpoint URL (http/https + host), then retry start/reconfigure."
    )
    #expect(
      Terra.TerraError(code: .persistence_setup_failed, message: "x").remediationHint
        == "Ensure persistence.storageURL points to a writable directory, then retry start/reconfigure."
    )
    #expect(
      Terra.TerraError(code: .already_started, message: "x").remediationHint
        == "Use Terra.reconfigure(...) for live updates, or call Terra.shutdown()/reset() before starting again."
    )
    #expect(
      Terra.TerraError(code: .invalid_lifecycle_state, message: "x").remediationHint
        == "Call lifecycle APIs only from valid states (for example: start before reconfigure/shutdown)."
    )
  }

  @Test("Unknown TerraError code falls back to a generic remediation hint")
  func unknownErrorHintFallback() {
    let error = Terra.TerraError(code: .init("custom_code"), message: "x")
    #expect(
      error.remediationHint
        == "Inspect TerraError.context and TerraError.underlying, then retry with corrected configuration/state."
    )
  }

  @Test("Workflow guidance errors point to the supported workflow APIs")
  func workflowGuidanceHints() {
    let wrongAPI = Terra.TerraError.wrongAPIForWorkflow(
      usedAPI: "Terra.stream(...).run",
      suggestedAPI: "Terra.workflow(name:id:_:)",
      why: "Tool work continues after the streaming callback returns.",
      example: "try await Terra.workflow(name: \"planner\") { workflow in }"
    )
    let propagation = Terra.TerraError.contextNotPropagated(
      reason: "Raw Task.detached does not inherit Terra task-local trace state.",
      fix: "Use SpanHandle.detached(...) from the workflow root to rebind the parent span."
    )

    #expect(wrongAPI.remediationHint.contains("Terra.workflow"))
    #expect(wrongAPI.recoverySuggestion.contains("Terra.workflow"))
    #expect(propagation.remediationHint.contains("detached"))
    #expect(propagation.recoverySuggestion.contains("SpanHandle.detached"))
  }
}
