import Foundation

public actor TraceStore {
  private struct SpanKey: Hashable {
    let traceID: TraceID
    let spanID: SpanID
  }

  private let maxSpans: Int
  private var spansByKey: [SpanKey: SpanRecord] = [:]
  private var insertionOrder: [SpanKey] = []

  public init(maxSpans: Int = 10_000) {
    self.maxSpans = max(0, maxSpans)
  }

  public func ingest(_ spans: [SpanRecord]) -> [SpanRecord] {
    guard !spans.isEmpty else { return [] }

    var accepted: [SpanRecord] = []
    accepted.reserveCapacity(spans.count)

    for span in spans {
      let key = SpanKey(traceID: span.traceID, spanID: span.spanID)
      if spansByKey[key] != nil { continue }
      spansByKey[key] = span
      insertionOrder.append(key)
      accepted.append(span)
    }

    enforceMaxSpans()
    return accepted
  }

  public func snapshot(filter: TraceFilter? = nil) -> TraceSnapshot {
    let filtered = spansByKey.values.filter { spanMatchesFilter($0, filter: filter) }
    let ordered = filtered.sorted(by: spanStreamSort)
    let grouped = Dictionary(grouping: ordered, by: { $0.traceID })
    let traces = grouped.mapValues { $0.sorted(by: spanTreeSort) }
    return TraceSnapshot(allSpans: ordered, traces: traces)
  }

  private func enforceMaxSpans() {
    guard maxSpans >= 0 else { return }
    while spansByKey.count > maxSpans {
      guard !insertionOrder.isEmpty else { break }
      let oldestKey = insertionOrder.removeFirst()
      spansByKey.removeValue(forKey: oldestKey)
    }
  }
}

private func spanStreamSort(_ lhs: SpanRecord, _ rhs: SpanRecord) -> Bool {
  let lhsEnd = endTimeUnixNano(lhs)
  let rhsEnd = endTimeUnixNano(rhs)
  if lhsEnd != rhsEnd { return lhsEnd < rhsEnd }

  let lhsTrace = idString(lhs.traceID)
  let rhsTrace = idString(rhs.traceID)
  if lhsTrace != rhsTrace { return lhsTrace < rhsTrace }

  let lhsSpan = idString(lhs.spanID)
  let rhsSpan = idString(rhs.spanID)
  if lhsSpan != rhsSpan { return lhsSpan < rhsSpan }

  return lhs.name < rhs.name
}

private func spanMatchesFilter(_ span: SpanRecord, filter: TraceFilter?) -> Bool {
  filter?.matches(span) ?? true
}

private func idString<T>(_ id: T) -> String {
  String(describing: id)
}

private func spanTreeSort(_ lhs: SpanRecord, _ rhs: SpanRecord) -> Bool {
  let lhsStart = startTimeUnixNano(lhs)
  let rhsStart = startTimeUnixNano(rhs)
  if lhsStart != rhsStart { return lhsStart < rhsStart }

  let lhsSpan = idString(lhs.spanID)
  let rhsSpan = idString(rhs.spanID)
  if lhsSpan != rhsSpan { return lhsSpan < rhsSpan }

  return lhs.name < rhs.name
}

private func startTimeUnixNano(_ span: SpanRecord) -> UInt64 {
  span.startTimeUnixNano
}

private func endTimeUnixNano(_ span: SpanRecord) -> UInt64 {
  span.endTimeUnixNano
}
