import InMemoryExporter
import OpenTelemetryApi
import OpenTelemetrySdk
import TerraCore

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
private final class ClosureOnlyContextManager: ContextManager {
  private struct TaskLocalContext: @unchecked Sendable {
    var values: [String: AnyObject] = [:]
  }

  @TaskLocal private static var context = TaskLocalContext()

  func getCurrentContextValue(forKey key: OpenTelemetryContextKeys) -> AnyObject? {
    Self.context.values[key.rawValue]
  }

  func setCurrentContextValue(forKey: OpenTelemetryContextKeys, value: AnyObject) {
    // Intentionally a no-op: this manager only supports the closure-based APIs.
  }

  func removeContextValue(forKey: OpenTelemetryContextKeys, value: AnyObject) {
    // Intentionally a no-op: this manager only supports the closure-based APIs.
  }

  func withCurrentContextValue<T>(
    forKey key: OpenTelemetryContextKeys,
    value: AnyObject?,
    _ operation: () throws -> T
  ) rethrows -> T {
    var context = Self.context
    context.values[key.rawValue] = value
    return try Self.$context.withValue(context, operation: operation)
  }

  func withCurrentContextValue<T>(
    forKey key: OpenTelemetryContextKeys,
    value: AnyObject?,
    _ operation: () async throws -> T
  ) async rethrows -> T {
    var context = Self.context
    context.values[key.rawValue] = value
    return try await Self.$context.withValue(context, operation: operation)
  }
}

final class TerraTestSupport {
  private let previousTracerProvider: any TracerProvider

  let tracerProvider: TracerProviderSdk
  let spanExporter: InMemoryExporter

  init() {
    Terra.lockTestingIsolation()
    previousTracerProvider = OpenTelemetry.instance.tracerProvider

    if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
      OpenTelemetry.registerContextManager(contextManager: ClosureOnlyContextManager())
    }

    spanExporter = InMemoryExporter()

    tracerProvider = TracerProviderSdk()
    tracerProvider.addSpanProcessor(SimpleSpanProcessor(spanExporter: spanExporter))

    OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
  }

  deinit {
    OpenTelemetry.registerTracerProvider(tracerProvider: previousTracerProvider)
    Terra.unlockTestingIsolation()
  }

  func finishedSpans() -> [SpanData] {
    tracerProvider.forceFlush()
    return spanExporter.getFinishedSpanItems()
  }

  func reset() {
    spanExporter.reset()
  }
}
