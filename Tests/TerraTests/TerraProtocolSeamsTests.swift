import Foundation
import Testing
@testable import TerraCore

@Suite("Protocol seams", .serialized)
struct TerraProtocolSeamsTests {
  @Test("Injected runtime/provider/executor seams capture deterministic instrumentation")
  func injectedSeamsCaptureDeterministicInstrumentation() async throws {
    let log = SeamLog()
    let runtime = MockRuntime(log: log)
    let provider = MockProvider(
      providerID: Terra.ProviderID("mock-provider"),
      runtimeID: Terra.RuntimeID("mock-runtime")
    )
    let executor = MockExecutor(log: log)

    let result = try await Terra
      .infer(Terra.ModelID("gpt-test"), prompt: "hello")
      .attr(.init("app.request.id"), "req-1")
      .run(using: runtime, provider: provider, executor: executor) { trace in
        trace.event("request.start")
        trace.attr(.init("app.phase"), "decode")
        trace.tokens(input: 5, output: 7)
        trace.responseModel(Terra.ModelID("gpt-test-response"))
        return "ok"
      }

    #expect(result == "ok")
    #expect(log.executorRuns == 1)
    #expect(log.beginDescriptors.count == 1)

    let descriptor = try #require(log.beginDescriptors.first)
    #expect(descriptor.kind == .inference)
    #expect(descriptor.model == Terra.ModelID("gpt-test"))
    #expect(descriptor.provider == Terra.ProviderID("mock-provider"))
    #expect(descriptor.runtime == Terra.RuntimeID("mock-runtime"))
    #expect(descriptor.capturePolicy == .default)

    #expect(log.events == ["request.start"])
    #expect(log.recordedAttributes[.init(name: "app.request.id", value: .string("req-1"))] == true)
    #expect(log.recordedAttributes[.init(name: "app.phase", value: .string("decode"))] == true)
    #expect(log.recordedAttributes[.init(name: Terra.Keys.GenAI.usageInputTokens, value: .int(5))] == true)
    #expect(log.recordedAttributes[.init(name: Terra.Keys.GenAI.usageOutputTokens, value: .int(7))] == true)
    #expect(log.recordedAttributes[.init(name: Terra.Keys.GenAI.responseModel, value: .string("gpt-test-response"))] == true)
    #expect(log.errors.isEmpty)
    #expect(log.finishCount == 1)
  }

  @Test("Injected seams record thrown errors without real transport")
  func injectedSeamsRecordThrownErrors() async {
    enum ExpectedError: Error { case boom }

    let log = SeamLog()
    let runtime = MockRuntime(log: log)
    let provider = MockProvider(providerID: nil, runtimeID: nil)
    let executor = MockExecutor(log: log)

    await #expect(throws: ExpectedError.self) {
      _ = try await Terra
        .tool("search", callID: Terra.ToolCallID("call-1"))
        .run(using: runtime, provider: provider, executor: executor) { _ in
          throw ExpectedError.boom
        }
    }

    #expect(log.executorRuns == 1)
    #expect(log.beginDescriptors.count == 1)
    #expect(log.errors.count == 1)
    #expect(log.finishCount == 1)
  }
}

private struct MockProvider: Terra.ProviderSeam {
  let providerID: Terra.ProviderID?
  let runtimeID: Terra.RuntimeID?

  func resolve(_ descriptor: Terra.CallDescriptor) -> Terra.CallDescriptor {
    var copy = descriptor
    copy.provider = providerID
    copy.runtime = runtimeID
    return copy
  }
}

private struct MockExecutor: Terra.ExecutorSeam {
  let log: SeamLog

  func execute<R: Sendable>(
    _ operation: @escaping @Sendable () async throws -> R
  ) async throws -> R {
    log.executorRuns += 1
    return try await operation()
  }
}

private struct MockRuntime: Terra.RuntimeSeam {
  let log: SeamLog

  func run<R: Sendable>(
    descriptor: Terra.CallDescriptor,
    attributes: [Terra.TraceAttribute],
    executor: any Terra.ExecutorSeam,
    _ body: @escaping @Sendable (Terra.TraceHandle) async throws -> R
  ) async throws -> R {
    log.beginDescriptors.append(descriptor)
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
      let result = try await executor.execute {
        try await body(handle)
      }
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

  private var _beginDescriptors: [Terra.CallDescriptor] = []
  private var _recordedAttributes: [Terra.TraceAttribute: Bool] = [:]
  private var _events: [String] = []
  private var _errors: [String] = []
  private var _executorRuns: Int = 0
  private var _finishCount: Int = 0

  var beginDescriptors: [Terra.CallDescriptor] {
    get { lock.withLock { _beginDescriptors } }
    set { lock.withLock { _beginDescriptors = newValue } }
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

  var executorRuns: Int {
    get { lock.withLock { _executorRuns } }
    set { lock.withLock { _executorRuns = newValue } }
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
