import Foundation
import Testing
@testable import TerraCore

@Suite("Protocol seams", .serialized)
struct TerraProtocolSeamsTests {
  @Test("Injected telemetry engine captures deterministic instrumentation")
  func injectedTelemetryEngineCapturesDeterministicInstrumentation() async throws {
    let log = SeamLog()
    let engine = MockEngine(log: log)

    let result = try await Terra
      .infer(
        Terra.ModelID("gpt-test"),
        prompt: "hello",
        provider: Terra.ProviderID("mock-provider"),
        runtime: Terra.RuntimeID("mock-runtime")
      )
      .attr(.init("app.request.id"), "req-1")
      .run(using: engine) { trace in
        trace.event("request.start")
        trace.attr(.init("app.phase"), "decode")
        trace.tokens(input: 5, output: 7)
        trace.responseModel(Terra.ModelID("gpt-test-response"))
        return "ok"
      }

    #expect(result == "ok")
    #expect(log.engineRuns == 1)
    #expect(log.beginContexts.count == 1)

    let context = try #require(log.beginContexts.first)
    #expect(context.operation == .inference)
    #expect(context.model == Terra.ModelID("gpt-test"))
    #expect(context.provider == Terra.ProviderID("mock-provider"))
    #expect(context.runtime == Terra.RuntimeID("mock-runtime"))
    #expect(context.capturePolicy == .default)

    #expect(log.events == ["request.start"])
    #expect(log.recordedAttributes[.init(name: "app.request.id", value: .string("req-1"))] == true)
    #expect(log.recordedAttributes[.init(name: "app.phase", value: .string("decode"))] == true)
    #expect(log.recordedAttributes[.init(name: Terra.Keys.GenAI.usageInputTokens, value: .int(5))] == true)
    #expect(log.recordedAttributes[.init(name: Terra.Keys.GenAI.usageOutputTokens, value: .int(7))] == true)
    #expect(log.recordedAttributes[.init(name: Terra.Keys.GenAI.responseModel, value: .string("gpt-test-response"))] == true)
    #expect(log.errors.isEmpty)
    #expect(log.finishCount == 1)
  }

  @Test("Injected engine records thrown errors without real transport")
  func injectedEngineRecordsThrownErrors() async {
    enum ExpectedError: Error { case boom }

    let log = SeamLog()
    let engine = MockEngine(log: log)

    await #expect(throws: ExpectedError.self) {
      _ = try await Terra
        .tool("search", callID: Terra.ToolCallID("call-1"))
        .run(using: engine) { _ in
          throw ExpectedError.boom
        }
    }

    #expect(log.engineRuns == 1)
    #expect(log.beginContexts.count == 1)
    #expect(log.errors.count == 1)
    #expect(log.finishCount == 1)
  }
}

private struct MockEngine: Terra.TelemetryEngine {
  let log: SeamLog

  func run<R: Sendable>(
    context: Terra.TelemetryContext,
    attributes: [Terra.TraceAttribute],
    _ body: @escaping @Sendable (Terra.TraceHandle) async throws -> R
  ) async throws -> R {
    log.beginContexts.append(context)
    var merged = log.recordedAttributes
    for attribute in attributes {
      merged[attribute] = true
    }
    log.recordedAttributes = merged

    let handle = Terra.TraceHandle(
      onEvent: { log.events.append($0) },
      onAttribute: { name, value in log.recordedAttributes[.init(name: name, value: value)] = true },
      onError: { log.errors.append(String(describing: $0)) },
      onTokens: { input, output in
        if let input { log.recordedAttributes[.init(name: Terra.Keys.GenAI.usageInputTokens, value: .int(input))] = true }
        if let output { log.recordedAttributes[.init(name: Terra.Keys.GenAI.usageOutputTokens, value: .int(output))] = true }
      },
      onResponseModel: { log.recordedAttributes[.init(name: Terra.Keys.GenAI.responseModel, value: .string($0.rawValue))] = true }
    )

    do {
      log.engineRuns += 1
      let result = try await body(handle)
      log.finishCount += 1
      return result
    } catch {
      log.errors.append(String(describing: error))
      log.finishCount += 1
      throw error
    }
  }
}

private final class SeamLog: @unchecked Sendable {
  private let lock = NSLock()

  private var _beginContexts: [Terra.TelemetryContext] = []
  private var _recordedAttributes: [Terra.TraceAttribute: Bool] = [:]
  private var _events: [String] = []
  private var _errors: [String] = []
  private var _engineRuns: Int = 0
  private var _finishCount: Int = 0

  var beginContexts: [Terra.TelemetryContext] {
    get { lock.withLock { _beginContexts } }
    set { lock.withLock { _beginContexts = newValue } }
  }

  var recordedAttributes: [Terra.TraceAttribute: Bool] {
    get { lock.withLock { _recordedAttributes } }
    set { lock.withLock { _recordedAttributes = newValue } }
  }

  var events: [String] {
    get { lock.withLock { _events } }
    set { lock.withLock { _events = newValue } }
  }

  var errors: [String] {
    get { lock.withLock { _errors } }
    set { lock.withLock { _errors = newValue } }
  }

  var engineRuns: Int {
    get { lock.withLock { _engineRuns } }
    set { lock.withLock { _engineRuns = newValue } }
  }

  var finishCount: Int {
    get { lock.withLock { _finishCount } }
    set { lock.withLock { _finishCount = newValue } }
  }
}

private extension NSLock {
  func withLock<R>(_ body: () throws -> R) rethrows -> R {
    lock()
    defer { unlock() }
    return try body()
  }
}
