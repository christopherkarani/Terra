import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

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

  /// Loads and groups spans into trace models.
  public func loadTraces() throws -> [Trace] {
    let files = try locator.listTraceFiles()
    var traces = [Trace]()

    for file in files {
      let spans: [SpanData]
      do {
        let data = try reader.read(file: file)
        spans = try decoder.decodeSpans(from: data)
      } catch {
        // Skip unreadable/corrupt files so one bad trace does not hide valid traces.
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

    return traces
  }
}
