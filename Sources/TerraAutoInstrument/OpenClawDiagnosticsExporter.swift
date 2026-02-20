import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import TerraCore

enum OpenClawDiagnosticsExporter {
  private static let lock = NSLock()
  private static var installed = false

  static func installIfNeeded(configuration: Terra.OpenClawConfiguration) {
    guard configuration.shouldEnableDiagnosticsExport else { return }
    guard let directoryURL = configuration.diagnosticsDirectoryURL else { return }
    guard let provider = OpenTelemetry.instance.tracerProvider as? TracerProviderSdk else { return }

    lock.lock()
    defer { lock.unlock() }
    guard !installed else { return }
    installed = true

    let exporter = DiagnosticsJSONLSpanExporter(directoryURL: directoryURL)
    provider.addSpanProcessor(SimpleSpanProcessor(spanExporter: exporter))
  }
}

private final class DiagnosticsJSONLSpanExporter: SpanExporter {
  private let directoryURL: URL
  private let lock = NSLock()

  init(directoryURL: URL) {
    self.directoryURL = directoryURL
  }

  func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
    _ = explicitTimeout
    guard !spans.isEmpty else { return .success }

    lock.lock()
    defer { lock.unlock() }

    do {
      try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
      let targetFile = fileURL(for: Date())
      if !FileManager.default.fileExists(atPath: targetFile.path) {
        FileManager.default.createFile(atPath: targetFile.path, contents: nil)
      }

      let handle = try FileHandle(forWritingTo: targetFile)
      defer { try? handle.close() }
      try handle.seekToEnd()

      let encoder = JSONEncoder()
      for span in spans where isRelevantOpenClawSpan(span) {
        let data = try encoder.encode(span)
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data("\n".utf8))
      }

      return .success
    } catch {
      return .failure
    }
  }

  func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
    _ = explicitTimeout
    return .success
  }

  func shutdown(explicitTimeout: TimeInterval?) {
    _ = explicitTimeout
  }

  private func fileURL(for date: Date) -> URL {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    let dayString = formatter.string(from: date)
    return directoryURL.appendingPathComponent("openclaw-\(dayString).jsonl", isDirectory: false)
  }

  private func isRelevantOpenClawSpan(_ span: SpanData) -> Bool {
    if span.attributes[Terra.Keys.Terra.openClawGateway] == .bool(true) {
      return true
    }
    if span.attributes[Terra.Keys.Terra.runtime] == .string("openclaw_gateway") {
      return true
    }
    if span.attributes[Terra.Keys.GenAI.providerName] == .string("openclaw") {
      return true
    }
    return false
  }
}
