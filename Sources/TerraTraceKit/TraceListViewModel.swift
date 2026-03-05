import Foundation

/// View model for trace list filtering and selection.
@MainActor
final class TraceListViewModel {
  /// All known traces.
  private(set) var traces: [Trace]
  /// Traces after filtering and sorting.
  private(set) var filteredTraces: [Trace]
  /// Current search query used for filtering.
  var searchQuery: String {
    didSet {
      applyFilter()
    }
  }
  /// Currently selected trace.
  private(set) var selectedTrace: Trace?

  /// Pre-sorted traces cache — re-sorted only when traces change.
  private var sortedTraces: [Trace] = []

  /// Creates a view model with an initial set of traces.
  init(traces: [Trace]) {
    self.traces = traces
    self.searchQuery = ""
    self.filteredTraces = []
    self.sortedTraces = traces.sorted { $0.fileTimestamp > $1.fileTimestamp }
    applyFilter()
  }

  /// Replaces the trace list and re-applies filtering.
  func updateTraces(_ traces: [Trace]) {
    self.traces = traces
    self.sortedTraces = traces.sorted { $0.fileTimestamp > $1.fileTimestamp }
    applyFilter()
  }

  /// Selects a trace by identifier.
  func selectTrace(id: String) {
    selectedTrace = filteredTraces.first { $0.id == id }
  }

  private func applyFilter() {
    let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !query.isEmpty else {
      filteredTraces = sortedTraces
      return
    }

    filteredTraces = sortedTraces.filter { trace in
      trace.id.lowercased().contains(query)
        || trace.displayName.lowercased().contains(query)
        || trace.traceID.hexString.lowercased().contains(query)
    }
  }
}
