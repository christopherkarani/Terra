import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import TerraCore

enum OpenClawDiagnosticsExporter {
  private static let lock = NSLock()
  private static var installedProviderID: ObjectIdentifier?
  private static var diagnosticsDirectoryURL: URL?

  static func configure(configuration: Terra.OpenClawConfiguration) {
    let directoryURL = configuration.shouldEnableDiagnosticsExport
      ? configuration.diagnosticsDirectoryURL
      : nil

    lock.lock()
    diagnosticsDirectoryURL = directoryURL
    lock.unlock()

    guard let provider = OpenTelemetry.instance.tracerProvider as? TracerProviderSdk else { return }

    let providerID = ObjectIdentifier(provider)
    lock.lock()
    defer { lock.unlock() }
    guard installedProviderID != providerID else { return }
    installedProviderID = providerID

    let exporter = DiagnosticsJSONLSpanExporter(directoryURL: { currentDiagnosticsDirectoryURL() })
    provider.addSpanProcessor(SimpleSpanProcessor(spanExporter: exporter))
  }

  private static func currentDiagnosticsDirectoryURL() -> URL? {
    lock.lock()
    defer { lock.unlock() }
    return diagnosticsDirectoryURL
  }
}

private final class DiagnosticsJSONLSpanExporter: SpanExporter {
  private let directoryURL: @Sendable () -> URL?
  private let lock = NSLock()
  private let encoder = JSONEncoder()

  init(directoryURL: @escaping @Sendable () -> URL?) {
    self.directoryURL = directoryURL
  }

  func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
    _ = explicitTimeout
    guard !spans.isEmpty else { return .success }

    guard let directoryURL = directoryURL() else { return .success }

    lock.lock()
    defer { lock.unlock() }

    do {
      try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
      let targetFile = fileURL(in: directoryURL, for: Date())
      if !FileManager.default.fileExists(atPath: targetFile.path) {
        FileManager.default.createFile(atPath: targetFile.path, contents: nil)
      }

      let handle = try FileHandle(forWritingTo: targetFile)
      defer { try? handle.close() }
      try handle.seekToEnd()

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

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private func fileURL(in directoryURL: URL, for date: Date) -> URL {
    let dayString = Self.dayFormatter.string(from: date)
    return directoryURL.appendingPathComponent("openclaw-\(dayString).jsonl", isDirectory: false)
  }

  private func isRelevantOpenClawSpan(_ span: SpanData) -> Bool {
    // Require the explicit gateway marker or gateway runtime attribute.
    // Provider name alone is not sufficient — regular inference spans routed through
    // the OpenClaw provider would be incorrectly exported to the diagnostics path.
    if span.attributes[Terra.Keys.Terra.openClawGateway] == .bool(true) {
      return true
    }
    if span.attributes[Terra.Keys.Terra.runtime] == .string("openclaw_gateway") {
      return true
    }
    return false
  }
}
