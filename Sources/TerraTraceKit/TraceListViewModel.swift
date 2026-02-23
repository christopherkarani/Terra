import Foundation

/// View model for trace list filtering and selection.
public final class TraceListViewModel {
  /// All known traces.
  public private(set) var traces: [Trace]
  /// Traces after filtering and sorting.
  public private(set) var filteredTraces: [Trace]
  /// Current search query used for filtering.
  public var searchQuery: String {
    didSet {
      applyFilter()
    }
  }
  /// Currently selected trace.
  public private(set) var selectedTrace: Trace?

  /// Creates a view model with an initial set of traces.
  public init(traces: [Trace]) {
    self.traces = traces
    self.searchQuery = ""
    self.filteredTraces = []
    applyFilter()
  }

  /// Replaces the trace list and re-applies filtering.
  public func updateTraces(_ traces: [Trace]) {
    self.traces = traces
    applyFilter()
  }

  /// Selects a trace by identifier.
  public func selectTrace(id: String) {
    selectedTrace = filteredTraces.first { $0.id == id }
  }

  private func applyFilter() {
    let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let base = traces.sorted { $0.fileTimestamp > $1.fileTimestamp }
    guard !query.isEmpty else {
      filteredTraces = base
      reconcileSelection()
      return
    }

    filteredTraces = base.filter { trace in
      trace.id.lowercased().contains(query)
        || trace.displayName.lowercased().contains(query)
        || trace.traceId.hexString.lowercased().contains(query)
    }
    reconcileSelection()
  }

  private func reconcileSelection() {
    guard let selectedTrace else { return }
    if let updated = filteredTraces.first(where: { $0.id == selectedTrace.id }) {
      self.selectedTrace = updated
    } else {
      self.selectedTrace = nil
    }
  }
}
