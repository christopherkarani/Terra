import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

/// Result of loading traces, including any per-file failures.
public struct TraceLoadResult {
  public let traces: [Trace]
  public let failures: [(file: URL, error: Error)]
}

/// Loads traces from persisted files using a locator, reader, and decoder.
public struct TraceLoader {
  public let locator: TraceFileLocator
  public let reader: TraceFileReader
  public let decoder: TraceDecoder

  /// Creates a loader with injectable persistence components.
  public init(
    locator: TraceFileLocator = TraceFileLocator(),
    reader: TraceFileReader = TraceFileReader(),
    decoder: TraceDecoder = TraceDecoder()
  ) {
    self.locator = locator
    self.reader = reader
    self.decoder = decoder
  }

  /// Loads and groups spans into trace models, reporting per-file failures.
  public func loadTracesWithFailures() throws -> TraceLoadResult {
    let files = try locator.listTraceFiles()
    var traces = [Trace]()
    var failures = [(file: URL, error: Error)]()

    for file in files {
      let spans: [SpanData]
      do {
        let data = try reader.read(file: file)
        spans = try decoder.decodeSpans(from: data)
      } catch {
        failures.append((file: file.url, error: error))
        continue
      }

      if spans.isEmpty {
        continue
      }

      let grouped = Dictionary(grouping: spans, by: { $0.traceId })
      for (traceId, groupSpans) in grouped {
        let id = "\(file.fileName)-\(traceId.hexString)"
        if let trace = try? Trace(fileName: id, spans: groupSpans) {
          traces.append(trace)
        }
      }
    }

    return TraceLoadResult(traces: traces, failures: failures)
  }

  /// Loads and groups spans into trace models (legacy convenience; discards failures).
  public func loadTraces() throws -> [Trace] {
    try loadTracesWithFailures().traces
  }
}
