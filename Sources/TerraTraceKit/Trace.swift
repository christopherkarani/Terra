import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

/// Errors thrown when assembling a trace model from spans.
public enum TraceModelError: Error, Equatable {
  case emptySpans
  case invalidFileName
  case mismatchedTraceIds
  case duplicateSpanIds
}

/// Aggregated trace metadata derived from persisted spans.
public struct Trace {
  /// Stable identifier derived from the persistence filename.
  public let id: String
  /// Timestamp derived from the leading digits of the persistence filename.
  public let fileTimestamp: Date
  /// Trace identifier shared by all spans in this trace.
  public let traceId: TraceId
  /// All spans belonging to this trace.
  public let spans: [SpanData]
  /// Spans sorted by start time, then end time.
  public let orderedSpans: [SpanData]
  /// Spans that have no parent span in this trace.
  public let rootSpans: [SpanData]
  /// Earliest span start time.
  public let startTime: Date
  /// Latest span end time.
  public let endTime: Date
  /// Total trace duration.
  public let duration: TimeInterval
  /// True if any span has error status.
  public let hasError: Bool
  /// Human-friendly name derived from root span or first span.
  public let displayName: String

  /// Builds a trace from a filename and its decoded spans.
  public init(fileName: String, spans: [SpanData]) throws {
    guard !spans.isEmpty else {
      throw TraceModelError.emptySpans
    }

    guard let fileTimestamp = TraceFileNameParser.timestamp(from: fileName) else {
      throw TraceModelError.invalidFileName
    }

    let traceId = spans[0].traceId
    if spans.contains(where: { $0.traceId != traceId }) {
      throw TraceModelError.mismatchedTraceIds
    }
    if Set(spans.map(\.spanId)).count != spans.count {
      throw TraceModelError.duplicateSpanIds
    }

    let ordered = spans.sorted { lhs, rhs in
      if lhs.startTime == rhs.startTime {
        return lhs.endTime < rhs.endTime
      }
      return lhs.startTime < rhs.startTime
    }

    // Single-pass extraction of start, end, roots, hasError
    var start = ordered[0].startTime
    var end = ordered[0].endTime
    var roots: [SpanData] = []
    var hasError = false
    for span in ordered {
      if span.startTime < start { start = span.startTime }
      if span.endTime > end { end = span.endTime }
      if span.parentSpanId == nil { roots.append(span) }
      if span.status.isError { hasError = true }
    }

    self.id = fileName
    self.fileTimestamp = fileTimestamp
    self.traceId = traceId
    self.spans = spans
    self.orderedSpans = ordered
    self.rootSpans = roots
    self.startTime = start
    self.endTime = end
    self.duration = end.timeIntervalSince(start)
    self.hasError = hasError
    self.displayName = roots.first?.name ?? ordered.first?.name ?? traceId.hexString
  }
}

enum TraceFileNameParser {
  static func timestamp(from fileName: String) -> Date? {
    let digits = fileName.prefix { $0.isNumber }
    guard !digits.isEmpty, let milliseconds = UInt64(digits) else {
      return nil
    }
    return Date(timeIntervalSinceReferenceDate: TimeInterval(milliseconds) / 1000.0)
  }
}
