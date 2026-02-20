import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

enum SampleTraces {
  static func writeSampleTrace(to directoryURL: URL) throws {
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    let fileName = Self.sampleFileName()
    let fileURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)

    let spans = try makeSpans()
    let encoded = try JSONEncoder().encode(spans)

    var fileData = Data(encoded)
    fileData.append(Data(",".utf8))
    try fileData.write(to: fileURL, options: [.atomic])
  }

  private static func sampleFileName() -> String {
    let milliseconds = UInt64(Date().timeIntervalSinceReferenceDate * 1000.0)
    return String(milliseconds)
  }

  private static func makeSpans() throws -> [SpanData] {
    let exporter = CollectingSpanExporter()
    let processor = SimpleSpanProcessor(spanExporter: exporter)
    let tracerProvider = TracerProviderSdk(spanProcessors: [processor])
    let tracer = tracerProvider.get(instrumentationName: "com.terra.trace-mac-app", instrumentationVersion: "sample")

    let start = Date()
    let agentStart = start
    let agentEnd = start.addingTimeInterval(0.420)

    let inferenceStart = start.addingTimeInterval(0.020)
    let inferenceEnd = start.addingTimeInterval(0.240)

    let toolStart = start.addingTimeInterval(0.260)
    let toolEnd = start.addingTimeInterval(0.380)

    let agentSpan = tracer
      .spanBuilder(spanName: "gen_ai.agent")
      .setNoParent()
      .setSpanKind(spanKind: .internal)
      .setStartTime(time: agentStart)
      .startSpan()
    agentSpan.setAttribute(key: "gen_ai.agent.name", value: "SupportAgent")
    agentSpan.setAttribute(key: "gen_ai.operation.name", value: "invoke")

    try OpenTelemetry.instance.contextProvider.withActiveSpan(agentSpan) {
      let inferenceSpan = tracer
        .spanBuilder(spanName: "gen_ai.inference")
        .setSpanKind(spanKind: .client)
        .setStartTime(time: inferenceStart)
        .startSpan()
      inferenceSpan.setAttribute(key: "gen_ai.model", value: "local/llama-3.2-1b")
      inferenceSpan.setAttribute(key: "terra.runtime", value: "sample")
      inferenceSpan.end(time: inferenceEnd)

      let toolSpan = tracer
        .spanBuilder(spanName: "gen_ai.tool")
        .setSpanKind(spanKind: .client)
        .setStartTime(time: toolStart)
        .startSpan()
      toolSpan.setAttribute(key: "gen_ai.tool.name", value: "search")
      toolSpan.setAttribute(key: "gen_ai.tool.call.id", value: "call-1")
      toolSpan.end(time: toolEnd)
    }

    agentSpan.end(time: agentEnd)
    tracerProvider.forceFlush()

    return exporter.exportedSpans.sorted { $0.startTime < $1.startTime }
  }
}

private final class CollectingSpanExporter: SpanExporter {
  private let lock = NSLock()
  private(set) var exportedSpans: [SpanData] = []

  func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
    lock.lock()
    defer { lock.unlock() }
    exportedSpans.append(contentsOf: spans)
    return .success
  }

  func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
    .success
  }

  func shutdown(explicitTimeout: TimeInterval?) {}
}
