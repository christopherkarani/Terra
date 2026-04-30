import Foundation

public actor TraceStore {
  private struct SpanKey: Hashable {
    let traceID: TraceID
    let spanID: SpanID
  }

  private let maxSpans: Int
  private var spansByKey: [SpanKey: SpanRecord] = [:]
  /// Per-trace span keys in arrival order. Lets eviction remove an entire
  /// trace's spans together so children are not orphaned (P1-13).
  private var spanKeysByTrace: [TraceID: [SpanKey]] = [:]
  /// Order in which trace IDs were first seen. Used as the LRU axis when
  /// choosing which trace to evict.
  private var traceOrder: [TraceID] = []
  private var traceOrderHead: Int = 0
  private var cachedSnapshot: TraceSnapshot?
  private var snapshotDirty = true

  public init(maxSpans: Int = 10_000) {
    self.maxSpans = max(0, maxSpans)
  }

  public func ingest(_ spans: [SpanRecord]) -> [SpanRecord] {
    guard !spans.isEmpty else { return [] }

    var accepted: [SpanRecord] = []
    accepted.reserveCapacity(spans.count)

    var didChange = false
    for span in spans {
      let key = SpanKey(traceID: span.traceID, spanID: span.spanID)
      if let existing = spansByKey[key] {
        let preferred = preferredSpan(existing: existing, candidate: span)
        guard preferred != existing else { continue }
        spansByKey[key] = preferred
        accepted.append(preferred)
        didChange = true
      } else {
        spansByKey[key] = span
        if spanKeysByTrace[span.traceID] == nil {
          spanKeysByTrace[span.traceID] = [key]
          traceOrder.append(span.traceID)
        } else {
          spanKeysByTrace[span.traceID]?.append(key)
        }
        accepted.append(span)
        didChange = true
      }
    }

    guard didChange else { return [] }
    enforceMaxSpans()
    snapshotDirty = true
    return accepted
  }

  public func snapshot(filter: TraceFilter? = nil) -> TraceSnapshot {
    if filter == nil, let cached = cachedSnapshot, !snapshotDirty {
      return cached
    }
    let filtered = spansByKey.values.filter { spanMatchesFilter($0, filter: filter) }
    let ordered = filtered.sorted(by: spanStreamSort)
    let grouped = Dictionary(grouping: ordered, by: { $0.traceID })
    let traces = grouped.mapValues { $0.sorted(by: spanTreeSort) }
    let snap = TraceSnapshot(allSpans: ordered, traces: traces)
    if filter == nil {
      cachedSnapshot = snap
      snapshotDirty = false
    }
    return snap
  }

  /// Evict whole traces (oldest first) until total span count fits under
  /// `maxSpans`. Removing a trace as a unit prevents orphaned children when
  /// only some of a trace's spans would otherwise be dropped (P1-13).
  private func enforceMaxSpans() {
    guard maxSpans > 0 else { return }
    while spansByKey.count > maxSpans {
      guard let traceID = nextEvictableTraceID() else { break }
      guard let keys = spanKeysByTrace.removeValue(forKey: traceID), !keys.isEmpty else {
        // Trace already drained; advance the LRU pointer and retry.
        continue
      }
      for key in keys {
        spansByKey.removeValue(forKey: key)
      }
    }
    // Compact when half of the trace-order array has been consumed.
    if traceOrderHead > traceOrder.count / 2, traceOrderHead > 0 {
      traceOrder.removeFirst(traceOrderHead)
      traceOrderHead = 0
    }
  }

  private func nextEvictableTraceID() -> TraceID? {
    while traceOrderHead < traceOrder.count {
      let traceID = traceOrder[traceOrderHead]
      traceOrderHead += 1
      if spanKeysByTrace[traceID] != nil {
        return traceID
      }
    }
    return nil
  }
}

private func preferredSpan(existing: SpanRecord, candidate: SpanRecord) -> SpanRecord {
  let existingScore = spanCompletenessScore(existing)
  let candidateScore = spanCompletenessScore(candidate)
  if candidateScore != existingScore {
    return candidateScore > existingScore ? candidate : existing
  }
  if candidate.endTimeUnixNano != existing.endTimeUnixNano {
    return candidate.endTimeUnixNano > existing.endTimeUnixNano ? candidate : existing
  }
  return existing
}

private func spanCompletenessScore(_ span: SpanRecord) -> Int {
  var score = 0
  if span.endTimeUnixNano > 0 { score += 1_000_000 }
  if span.parentSpanID != nil { score += 1_000 }
  if span.status != .unset { score += 100 }
  if span.statusDescription != nil { score += 10 }
  score += span.attributes.items.count
  score += span.resource.attributes.items.count
  score += span.events.count
  score += span.links.count
  return score
}

private func spanStreamSort(_ lhs: SpanRecord, _ rhs: SpanRecord) -> Bool {
  let lhsEnd = endTimeUnixNano(lhs)
  let rhsEnd = endTimeUnixNano(rhs)
  if lhsEnd != rhsEnd { return lhsEnd < rhsEnd }

  if lhs.traceID != rhs.traceID { return lhs.traceID < rhs.traceID }
  if lhs.spanID != rhs.spanID { return lhs.spanID < rhs.spanID }

  return lhs.name < rhs.name
}

private func spanMatchesFilter(_ span: SpanRecord, filter: TraceFilter?) -> Bool {
  filter?.matches(span) ?? true
}

private func spanTreeSort(_ lhs: SpanRecord, _ rhs: SpanRecord) -> Bool {
  let lhsStart = startTimeUnixNano(lhs)
  let rhsStart = startTimeUnixNano(rhs)
  if lhsStart != rhsStart { return lhsStart < rhsStart }

  if lhs.spanID != rhs.spanID { return lhs.spanID < rhs.spanID }

  return lhs.name < rhs.name
}

private func startTimeUnixNano(_ span: SpanRecord) -> UInt64 {
  span.startTimeUnixNano
}

private func endTimeUnixNano(_ span: SpanRecord) -> UInt64 {
  span.endTimeUnixNano
}
