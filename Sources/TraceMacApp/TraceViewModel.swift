import Foundation
import TerraTraceKit

@MainActor
final class TraceViewModel {
  private let traceStore: TraceStore
  private let filter: TraceFilter?

  private(set) var snapshot: TraceSnapshot
  var selectedTraceID: TraceID? {
    didSet {
      guard selectedTraceID != oldValue else { return }
      selectedSpanID = nil
    }
  }
  var selectedSpanID: SpanID? {
    didSet {
      guard let selectedSpanID else { return }
      guard let selectedTraceID, spanExists(selectedSpanID, in: selectedTraceID) else {
        self.selectedSpanID = nil
        return
      }
    }
  }

  init(traceStore: TraceStore, filter: TraceFilter? = nil) {
    self.traceStore = traceStore
    self.filter = filter
    self.snapshot = TraceSnapshot(allSpans: [], traces: [:])
  }

  func refresh() async {
    let latest = await traceStore.snapshot(filter: filter)
    snapshot = latest
    reconcileSelectionAfterRefresh()
  }

  private func reconcileSelectionAfterRefresh() {
    guard let selectedTraceID else {
      selectedSpanID = nil
      return
    }

    guard snapshot.traces[selectedTraceID] != nil else {
      self.selectedTraceID = nil
      return
    }

    if let selectedSpanID, !spanExists(selectedSpanID, in: selectedTraceID) {
      self.selectedSpanID = nil
    }
  }

  private func spanExists(_ spanID: SpanID, in traceID: TraceID) -> Bool {
    guard let spans = snapshot.traces[traceID] else { return false }
    return spans.contains { $0.spanID == spanID }
  }
}

struct TraceTimelineModel: Sendable {
  struct Item: Sendable, Hashable {
    let spanID: SpanID
    let name: String
    let status: StatusCode
    let normalizedStart: Double
    let normalizedDuration: Double
  }

  let items: [Item]

  init(spans: [SpanRecord]) {
    guard !spans.isEmpty else {
      self.items = []
      return
    }

    let minStart = spans.map(\.startTimeUnixNano).min() ?? 0
    let maxEnd = spans.map(\.endTimeUnixNano).max() ?? minStart
    let range = maxEnd >= minStart ? (maxEnd - minStart) : 0
    let denominator = range > 0 ? Double(range) : 0

    let ordered = spans.sorted(by: spanTimelineSort)
    self.items = ordered.map { span in
      let normalizedStart: Double
      let normalizedDuration: Double
      if denominator > 0 {
        normalizedStart = Double(span.startTimeUnixNano - minStart) / denominator
        normalizedDuration = Double(span.durationNanoseconds) / denominator
      } else {
        normalizedStart = 0
        normalizedDuration = 0
      }
      return Item(
        spanID: span.spanID,
        name: span.name,
        status: span.status,
        normalizedStart: normalizedStart,
        normalizedDuration: normalizedDuration
      )
    }
  }
}

private func spanTimelineSort(_ lhs: SpanRecord, _ rhs: SpanRecord) -> Bool {
  let lhsStart = lhs.startTimeUnixNano
  let rhsStart = rhs.startTimeUnixNano
  if lhsStart != rhsStart { return lhsStart < rhsStart }

  let lhsSpan = String(describing: lhs.spanID)
  let rhsSpan = String(describing: rhs.spanID)
  if lhsSpan != rhsSpan { return lhsSpan < rhsSpan }

  return lhs.name < rhs.name
}
