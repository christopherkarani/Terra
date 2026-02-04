import Foundation
import TerraTraceKit

@MainActor
final class TraceViewModel {
  private let traceStore: TraceStore
  private let filter: TraceFilter?
  private(set) var searchFilter: TraceFilter?

  private(set) var snapshot: TraceSnapshot
  var spanListItems: [SpanRecord] {
    guard let selectedTraceID else { return [] }
    let spans = snapshot.traces[selectedTraceID] ?? []
    return spans.sorted(by: spanTimelineSort)
  }
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
  var selectedSpan: SpanRecord? {
    guard let selectedTraceID, let selectedSpanID else { return nil }
    return snapshot.traces[selectedTraceID]?.first { $0.spanID == selectedSpanID }
  }

  init(traceStore: TraceStore, filter: TraceFilter? = nil) {
    self.traceStore = traceStore
    self.filter = filter
    self.snapshot = TraceSnapshot(allSpans: [], traces: [:])
  }

  func updateSearchQuery(_ query: String) {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      searchFilter = nil
      return
    }

    if trimmed.lowercased().hasPrefix("trace:") {
      let value = String(trimmed.dropFirst("trace:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
      if let traceID = TraceID(hex: value) {
        searchFilter = TraceFilter(traceID: traceID)
      } else {
        searchFilter = value.isEmpty ? nil : TraceFilter(namePrefix: value)
      }
      return
    }

    if trimmed.lowercased().hasPrefix("name:") {
      let value = String(trimmed.dropFirst("name:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
      searchFilter = value.isEmpty ? nil : TraceFilter(namePrefix: value)
      return
    }

    if let traceID = TraceID(hex: trimmed) {
      searchFilter = TraceFilter(traceID: traceID)
    } else {
      searchFilter = TraceFilter(namePrefix: trimmed)
    }
  }

  func selectNextSpan() {
    guard !spanListItems.isEmpty else { return }
    guard let selectedSpanID else {
      self.selectedSpanID = spanListItems.first?.spanID
      return
    }

    guard let index = spanListItems.firstIndex(where: { $0.spanID == selectedSpanID }) else {
      self.selectedSpanID = spanListItems.first?.spanID
      return
    }

    let nextIndex = min(index + 1, spanListItems.count - 1)
    self.selectedSpanID = spanListItems[nextIndex].spanID
  }

  func selectPreviousSpan() {
    guard !spanListItems.isEmpty else { return }
    guard let selectedSpanID else {
      self.selectedSpanID = spanListItems.last?.spanID
      return
    }

    guard let index = spanListItems.firstIndex(where: { $0.spanID == selectedSpanID }) else {
      self.selectedSpanID = spanListItems.last?.spanID
      return
    }

    let previousIndex = max(index - 1, 0)
    self.selectedSpanID = spanListItems[previousIndex].spanID
  }

  func refresh() async {
    let baseSnapshot = await traceStore.snapshot(filter: filter)
    snapshot = applySearchFilter(baseSnapshot, searchFilter: searchFilter)
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

  private func applySearchFilter(_ snapshot: TraceSnapshot, searchFilter: TraceFilter?) -> TraceSnapshot {
    guard let searchFilter else { return snapshot }
    let filtered = snapshot.allSpans.filter { searchFilter.matches($0) }
    let grouped = Dictionary(grouping: filtered, by: { $0.traceID })
    let traces = grouped.mapValues { $0.sorted(by: spanTimelineSort) }
    return TraceSnapshot(allSpans: filtered.sorted(by: spanTimelineSort), traces: traces)
  }
}

struct TraceTimelineModel: Sendable {
  struct Item: Sendable, Hashable {
    let spanID: SpanID
    let name: String
    let status: StatusCode
    let normalizedStart: Double
    let normalizedDuration: Double
    let isSelected: Bool
  }

  let items: [Item]

  init(spans: [SpanRecord], selectedSpanID: SpanID? = nil) {
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
        normalizedDuration: normalizedDuration,
        isSelected: span.spanID == selectedSpanID
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
