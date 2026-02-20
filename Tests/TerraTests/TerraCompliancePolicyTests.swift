import XCTest
@testable import TerraCore

final class TerraCompliancePolicyTests: XCTestCase {
  private var support: TerraTestSupport!

  override func setUp() {
    super.setUp()
    support = TerraTestSupport()
    _ = Runtime.shared.consumeAuditEvents()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))
  }

  override func tearDown() {
    _ = Runtime.shared.consumeAuditEvents()
    support.reset()
    super.tearDown()
  }

  func testWithInferenceSpan_blockedByPolicy_runsBodyWithoutExportingSpan_andEmitsAudit() async throws {
    Terra.install(
      .init(
        compliance: .init(
          exportControls: .init(
            enabled: true,
            blockOnViolation: true,
            allowedRuntimes: [.coreML]
          ),
          auditEnabled: true
        ),
        tracerProvider: support.tracerProvider,
        registerProvidersAsGlobal: false
      )
    )

    let request = Terra.InferenceRequest(
      model: "local/llama-3.2-1b",
      runtime: .ollama,
      requestID: "blocked-request"
    )
    var didRunBody = false

    await Terra.withInferenceSpan(request) { scope in
      didRunBody = true
      scope.addEvent("body.ran")
    }

    XCTAssertTrue(didRunBody)
    XCTAssertTrue(support.finishedSpans().isEmpty)

    let audits = Runtime.shared.consumeAuditEvents()
    XCTAssertEqual(audits.count, 1)
    XCTAssertEqual(audits.first?.message, "Telemetry span blocked by policy")
    XCTAssertEqual(audits.first?.attributes["reason"], "runtime_not_allowed")
    XCTAssertEqual(audits.first?.attributes["runtime"], Terra.RuntimeKind.ollama.rawValue)
    XCTAssertEqual(audits.first?.attributes["request_id"], "blocked-request")
  }

  func testWithInferenceSpan_policyViolationAnnotatesWhenBlockingDisabled() async throws {
    Terra.install(
      .init(
        compliance: .init(
          exportControls: .init(
            enabled: true,
            blockOnViolation: false,
            allowedRuntimes: [.coreML]
          ),
          auditEnabled: true
        ),
        tracerProvider: support.tracerProvider,
        registerProvidersAsGlobal: false
      )
    )

    let request = Terra.InferenceRequest(model: "local/llama-3.2-1b", runtime: .ollama)
    await Terra.withInferenceSpan(request) { _ in }

    let span = try XCTUnwrap(support.finishedSpans().first)
    XCTAssertEqual(span.attributes[Terra.Keys.Terra.policyBlocked]?.description, "true")
    XCTAssertEqual(span.attributes[Terra.Keys.Terra.policyReason]?.description, "runtime_not_allowed")
    XCTAssertEqual(span.attributes[Terra.Keys.Terra.runtime]?.description, Terra.RuntimeKind.ollama.rawValue)
  }

  func testWithAgentInvocationSpan_synthesizesRequiredTerraV1RootAttributes() async throws {
    await Terra.withAgentInvocationSpan(agent: .init(name: "router")) { _ in }

    let span = try XCTUnwrap(support.finishedSpans().first)
    XCTAssertNotNil(span.attributes[Terra.Keys.Terra.semanticVersion])
    XCTAssertNotNil(span.attributes[Terra.Keys.Terra.schemaFamily])
    XCTAssertNotNil(span.attributes[Terra.Keys.Terra.runtime])
    XCTAssertNotNil(span.attributes[Terra.Keys.Terra.requestID])
    XCTAssertNotNil(span.attributes[Terra.Keys.Terra.sessionID])
    XCTAssertNotNil(span.attributes[Terra.Keys.Terra.modelFingerprint])
    XCTAssertEqual(span.attributes[Terra.Keys.Terra.runtimeSynthesis]?.description, "true")
    XCTAssertEqual(span.attributes[Terra.Keys.Terra.modelFingerprintSynthesis]?.description, "true")
    XCTAssertEqual(span.attributes[Terra.Keys.Terra.controlLoopMode]?.description, "deterministic")
    XCTAssertEqual(span.attributes[Terra.Keys.Terra.eventAggregationLevel]?.description, "sampled")
  }

  func testEmitRecommendation_appliesCooldownAndDedupeByRecommendationID() async throws {
    var telemetry = Terra.TelemetryConfiguration.default
    telemetry.recommendationPolicy = .init(
      enabled: true,
      minConfidence: 0.5,
      cooldownSeconds: 120,
      dedupeWindowSeconds: 120,
      maxTrackedRecommendationIDs: 32
    )

    Terra.install(
      .init(
        telemetry: telemetry,
        tracerProvider: support.tracerProvider,
        registerProvidersAsGlobal: false
      )
    )

    let request = Terra.InferenceRequest(model: "coreml-model", runtime: .coreML)
    await Terra.withInferenceSpan(request) { scope in
      Terra.emitRecommendation(
        .init(
          id: "rec-thermal-1",
          kind: .thermalSlowdown,
          confidence: 0.9,
          action: "reduce_batch",
          reason: "thermal throttle"
        ),
        on: scope
      )
      Terra.emitRecommendation(
        .init(
          id: "rec-thermal-1",
          kind: .thermalSlowdown,
          confidence: 0.9,
          action: "reduce_batch",
          reason: "thermal throttle"
        ),
        on: scope
      )
    }

    let span = try XCTUnwrap(support.finishedSpans().first)
    let recommendationEvents = span.events.filter { $0.name == Terra.Keys.Terra.recommendationEvent }
    XCTAssertEqual(recommendationEvents.count, 1)
    XCTAssertEqual(
      recommendationEvents.first?.attributes[Terra.Keys.Terra.recommendationID]?.description,
      "rec-thermal-1"
    )
  }

  func testAuditBuffer_staysBoundedUnderPolicyPressure() async {
    Terra.install(
      .init(
        compliance: .init(
          exportControls: .init(
            enabled: true,
            blockOnViolation: true,
            allowedRuntimes: [.coreML]
          ),
          auditEnabled: true
        ),
        tracerProvider: support.tracerProvider,
        registerProvidersAsGlobal: false
      )
    )
    _ = Runtime.shared.consumeAuditEvents()

    for index in 0..<1_100 {
      let request = Terra.InferenceRequest(
        model: "local/llama-3.2-1b",
        runtime: .ollama,
        requestID: "pressure-\(index)"
      )
      await Terra.withInferenceSpan(request) { _ in }
    }

    XCTAssertTrue(support.finishedSpans().isEmpty)
    let audits = Runtime.shared.consumeAuditEvents()
    XCTAssertEqual(audits.count, 1_024)
    XCTAssertEqual(audits.first?.attributes["request_id"], "pressure-76")
    XCTAssertEqual(audits.last?.attributes["request_id"], "pressure-1099")
  }

  func testConcurrentPolicySuppression_isDeterministicAcrossRepeatedRounds() async {
    Terra.install(
      .init(
        compliance: .init(
          exportControls: .init(
            enabled: true,
            blockOnViolation: true,
            allowedRuntimes: [.coreML]
          ),
          auditEnabled: true
        ),
        tracerProvider: support.tracerProvider,
        registerProvidersAsGlobal: false
      )
    )

    let rounds = 3
    let requestsPerRound = 320
    var observedAuditCounts: [Int] = []
    var observedBodyExecutionCounts: [Int] = []

    for round in 0..<rounds {
      support.reset()
      _ = Runtime.shared.consumeAuditEvents()
      let counter = AsyncCounter()

      await withTaskGroup(of: Void.self) { group in
        for index in 0..<requestsPerRound {
          group.addTask {
            let request = Terra.InferenceRequest(
              model: "local/llama-3.2-1b",
              runtime: .ollama,
              requestID: "round-\(round)-\(index)"
            )
            await Terra.withInferenceSpan(request) { _ in
              await counter.increment()
            }
          }
        }
      }

      let executedBodies = await counter.value
      let spans = support.finishedSpans()
      let audits = Runtime.shared.consumeAuditEvents()

      XCTAssertTrue(spans.isEmpty, "Round \(round) should not export blocked spans")
      XCTAssertEqual(executedBodies, requestsPerRound, "Round \(round) should execute every blocked body")
      XCTAssertEqual(audits.count, requestsPerRound, "Round \(round) should emit deterministic audit counts")

      observedAuditCounts.append(audits.count)
      observedBodyExecutionCounts.append(executedBodies)
    }

    XCTAssertEqual(Set(observedAuditCounts), [requestsPerRound])
    XCTAssertEqual(Set(observedBodyExecutionCounts), [requestsPerRound])
  }
}

private actor AsyncCounter {
  private(set) var value = 0

  func increment() {
    value += 1
  }
}
