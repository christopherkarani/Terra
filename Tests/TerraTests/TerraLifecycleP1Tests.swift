import XCTest
import InMemoryExporter
import OpenTelemetryApi
import OpenTelemetrySdk
@testable import TerraCore

/// Tests for the four P1 Terra-core lifecycle issues:
/// - P1-1: `Terra.workflow` re-parents to ambient OTel spans without an opt-out.
/// - P1-2: Augmented OTel signposts processor is not gated by a `ProcessorGate`.
/// - P1-3: `_SpanRegistry` leaks across shutdown→start cycles.
/// - P1-7: Span enrichment processors skip user-named workflow spans.
final class TerraLifecycleP1Tests: XCTestCase {
  override func setUp() async throws {
    Terra.resetOpenTelemetryForTesting()
  }

  override func tearDown() async throws {
    Terra._shutdownOpenTelemetry()
  }

  // MARK: - P1-1: Workflow detach-from-ambient

  func testWorkflowDetachFromAmbient_doesNotInheritOTelActiveSpan() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    // Start an ambient OTel span outside Terra so the global context provider has an active span.
    let ambientTracer = support.tracerProvider.get(instrumentationName: "ambient-app")
    let ambientSpan = ambientTracer.spanBuilder(spanName: "ambient.app.root").startSpan()
    defer { ambientSpan.end() }

    try await OpenTelemetry.instance.contextProvider.withActiveSpan(ambientSpan) {
      // .detachFromAmbient should ignore the OTel ambient span entirely.
      try await Terra.workflow(
        name: "detached-workflow",
        id: "issue-detach",
        rootStrategy: .detachFromAmbient
      ) { span in
        XCTAssertNil(span.parentId, "Detached workflow root must have no parent")
        return ()
      }
    }

    let spans = support.finishedSpans()
    let detached = try XCTUnwrap(spans.first(where: { $0.name == "detached-workflow" }))

    XCTAssertNil(detached.parentSpanId, "Detached workflow root must not inherit ambient parent")
    XCTAssertEqual(
      detached.attributes["terra.workflow.root.detached_from_ambient"]?.description,
      "true"
    )

    // Sanity check: the default `.attachToAmbient` strategy still parents to ambient.
    try await OpenTelemetry.instance.contextProvider.withActiveSpan(ambientSpan) {
      try await Terra.workflow(
        name: "attached-workflow",
        id: "issue-attach",
        rootStrategy: .attachToAmbient
      ) { _ in () }
    }

    let attached = try XCTUnwrap(support.finishedSpans().first(where: { $0.name == "attached-workflow" }))
    XCTAssertEqual(
      attached.parentSpanId?.hexString,
      ambientSpan.context.spanId.hexString,
      "Default attachToAmbient should still parent under the ambient span"
    )
  }

  func testWorkflowDefaultStrategy_isAttachToAmbient_andBackCompat() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let ambientTracer = support.tracerProvider.get(instrumentationName: "ambient-app")
    let ambientSpan = ambientTracer.spanBuilder(spanName: "ambient.app.root").startSpan()
    defer { ambientSpan.end() }

    // Old API (no rootStrategy) must remain attachToAmbient.
    try await OpenTelemetry.instance.contextProvider.withActiveSpan(ambientSpan) {
      try await Terra.workflow(name: "legacy-workflow", id: "issue-legacy") { _ in () }
    }

    let spans = support.finishedSpans()
    let legacy = try XCTUnwrap(spans.first(where: { $0.name == "legacy-workflow" }))
    XCTAssertEqual(
      legacy.parentSpanId?.hexString,
      ambientSpan.context.spanId.hexString,
      "Legacy workflow API must keep current attach-to-ambient semantics"
    )
  }

  // MARK: - P1-3: Span registry shutdown purge

  func testSpanRegistry_isPurgedOnShutdown() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    // Start a manual workflow root span; do not end it.
    let span = Terra.startSpan(name: "leaky-root", id: "issue-leak")
    XCTAssertFalse(Terra.activeSpans().isEmpty, "Span must be in registry while running")
    let underlyingOtelSpan = span.otelSpan

    Terra._resetActiveSpansForLifecycle()

    // Registry must be empty and the underlying span must have been ended.
    XCTAssertTrue(Terra.activeSpans().isEmpty, "Span registry must be empty after lifecycle reset")
    XCTAssertFalse(underlyingOtelSpan.isRecording, "Underlying span must be ended after lifecycle reset")
  }

  func testSpanRegistry_lifecycleResetIsIdempotent() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    // Reset twice on an already-empty registry; must not crash.
    Terra._resetActiveSpansForLifecycle()
    Terra._resetActiveSpansForLifecycle()

    // Start one span, reset, then reset again.
    _ = Terra.startSpan(name: "double-reset-root", id: "issue-double")
    Terra._resetActiveSpansForLifecycle()
    Terra._resetActiveSpansForLifecycle()

    XCTAssertTrue(Terra.activeSpans().isEmpty)
  }

  func testShutdown_purgesSpanRegistry() async throws {
    // Real shutdown path must purge the registry.
    try Terra.installOpenTelemetry(p1MinimalConfig())

    let span = Terra.startSpan(name: "shutdown-leak", id: "issue-shutdown-leak")
    XCTAssertFalse(Terra.activeSpans().isEmpty)
    let underlyingOtelSpan = span.otelSpan

    Terra._shutdownOpenTelemetry()

    XCTAssertTrue(Terra.activeSpans().isEmpty, "Shutdown must clear span registry")
    XCTAssertFalse(underlyingOtelSpan.isRecording, "Shutdown must end leaked spans")
  }

  // MARK: - P1-7: Enrichment processor runs on user-named workflow spans

  func testEnrichmentProcessor_runsOnUserNamedWorkflowSpan() async throws {
    let exporter = InMemoryExporter()
    let provider = TracerProviderSdk()
    provider.addSpanProcessor(TerraSpanEnrichmentProcessor())
    provider.addSpanProcessor(SimpleSpanProcessor(spanExporter: exporter))

    Terra.lockTestingIsolation()
    let previous = OpenTelemetry.instance.tracerProvider
    OpenTelemetry.registerTracerProvider(tracerProvider: provider)
    defer {
      OpenTelemetry.registerTracerProvider(tracerProvider: previous)
      Terra.unlockTestingIsolation()
    }

    Terra.install(.init(tracerProvider: provider, registerProvidersAsGlobal: false))

    // Use a *user-defined* workflow name (NOT one of the canonical SpanNames.* values).
    try await Terra.workflow(name: "request-workflow", id: "issue-enrich") { _ in () }

    provider.forceFlush()
    let spans = exporter.getFinishedSpanItems()
    let workflow = try XCTUnwrap(spans.first(where: { $0.name == "request-workflow" }))

    // Privacy attributes must be present on the user-named workflow span.
    XCTAssertNotNil(
      workflow.attributes[Terra.Keys.Terra.contentPolicy],
      "Enrichment processor must run on user-named workflow spans (P1-7)"
    )
    XCTAssertNotNil(
      workflow.attributes[Terra.Keys.Terra.contentRedaction],
      "Enrichment processor must run on user-named workflow spans (P1-7)"
    )
  }

  // MARK: - P1-2: Signposts processor is gated on shutdown

  func testAugmentExistingShutdown_signpostsProcessorIsGated() async throws {
    // Borrow an existing global TracerProviderSdk that the test owns and
    // verify that after `_shutdownOpenTelemetry()` the augmented signposts
    // processor stops emitting events for new spans.
    let exporter = InMemoryExporter()
    let externalProvider = TracerProviderSdk()
    externalProvider.addSpanProcessor(SimpleSpanProcessor(spanExporter: exporter))

    Terra.lockTestingIsolation()
    let previous = OpenTelemetry.instance.tracerProvider
    OpenTelemetry.registerTracerProvider(tracerProvider: externalProvider)
    defer {
      OpenTelemetry.registerTracerProvider(tracerProvider: previous)
      Terra.unlockTestingIsolation()
    }

    let probe = SignpostsProbeProcessor()
    let config = Terra.OpenTelemetryConfiguration(
      tracerProviderStrategy: .augmentExisting,
      enableTraces: false,
      enableMetrics: false,
      enableLogs: false,
      enableSignposts: false, // we'll inject our own probe instead of OS signposts
      enableSessions: false,
      otlpTracesEndpoint: URL(string: "http://127.0.0.1:14098/v1/traces")!,
      otlpMetricsEndpoint: URL(string: "http://127.0.0.1:14098/v1/metrics")!,
      otlpLogsEndpoint: URL(string: "http://127.0.0.1:14098/v1/logs")!
    )
    try Terra.installOpenTelemetry(config)

    // Inject the probe through the same gate the signposts processor uses.
    Terra._installAugmentedSignpostsProcessorForTesting(probe)

    // Before shutdown: the probe sees onStart events.
    let preTracer = externalProvider.get(instrumentationName: "p1-test")
    let pre = preTracer.spanBuilder(spanName: "pre-shutdown").startSpan()
    pre.end()
    XCTAssertGreaterThan(probe.startedCount, 0, "Signposts probe should fire before shutdown")

    let preShutdownCount = probe.startedCount

    // Shutdown borrowed-provider: signposts processor must be gated off.
    Terra._shutdownOpenTelemetry()

    // After shutdown: new spans on the *borrowed* provider must NOT trigger the probe.
    let postTracer = externalProvider.get(instrumentationName: "p1-test")
    let post = postTracer.spanBuilder(spanName: "post-shutdown").startSpan()
    post.end()

    XCTAssertEqual(
      probe.startedCount,
      preShutdownCount,
      "Augmented signposts processor must be gated off after Terra shutdown (P1-2)"
    )
  }
}

// MARK: - Helpers

private func p1MinimalConfig(port: Int = 14096) -> Terra.OpenTelemetryConfiguration {
  Terra.OpenTelemetryConfiguration(
    enableTraces: false,
    enableMetrics: false,
    enableLogs: false,
    enableSignposts: false,
    enableSessions: false,
    otlpTracesEndpoint: URL(string: "http://127.0.0.1:\(port)/v1/traces")!,
    otlpMetricsEndpoint: URL(string: "http://127.0.0.1:\(port)/v1/metrics")!,
    otlpLogsEndpoint: URL(string: "http://127.0.0.1:\(port)/v1/logs")!
  )
}

/// Test-only `SpanProcessor` that counts `onStart` invocations. Used as a
/// stand-in for the OS signposts processor inside the augmented-tracing gate.
final class SignpostsProbeProcessor: SpanProcessor, @unchecked Sendable {
  var isStartRequired: Bool { true }
  var isEndRequired: Bool { false }

  private let lock = NSLock()
  private var _startedCount = 0

  var startedCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return _startedCount
  }

  func onStart(parentContext: SpanContext?, span: ReadableSpan) {
    lock.lock()
    _startedCount += 1
    lock.unlock()
  }

  func onEnd(span: ReadableSpan) {}
  func shutdown(explicitTimeout: TimeInterval?) {}
  func forceFlush(timeout: TimeInterval?) {}
}
