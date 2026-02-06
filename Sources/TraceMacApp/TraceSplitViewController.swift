import AppKit
import TerraTraceKit

final class TraceSplitViewController: NSSplitViewController {
  private let traceListViewController = TraceListViewController()
  private let timelineViewController = TraceTimelineViewController()
  private let spanInspectorViewController = SpanInspectorSplitViewController()
  private var tracesDirectoryURL: URL
  private var loader: TraceLoader

  private var traces: [Trace] = []
  private var selectedTrace: Trace?

  init(tracesDirectoryURL: URL = AppSettings.tracesDirectoryURL) {
    self.tracesDirectoryURL = tracesDirectoryURL
    self.loader = TraceLoader(locator: TraceFileLocator(tracesDirectoryURL: tracesDirectoryURL))
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    splitView.isVertical = true
    splitView.dividerStyle = .paneSplitter

    let listItem = NSSplitViewItem(viewController: traceListViewController)
    listItem.minimumThickness = 220
    listItem.maximumThickness = 360
    listItem.preferredThicknessFraction = 0.24
    let timelineItem = NSSplitViewItem(viewController: timelineViewController)
    let detailItem = NSSplitViewItem(viewController: spanInspectorViewController)
    detailItem.minimumThickness = 320
    detailItem.preferredThicknessFraction = 0.34

    addSplitViewItem(listItem)
    addSplitViewItem(timelineItem)
    addSplitViewItem(detailItem)

    traceListViewController.onSelectTrace = { [weak self] trace in
      self?.selectTrace(trace)
    }
    timelineViewController.onSelectSpan = { [weak self] span in
      self?.spanInspectorViewController.selectSpan(span)
      self?.spanInspectorViewController.selectSpanInList(span)
    }
    spanInspectorViewController.onSelectSpan = { [weak self] span in
      self?.timelineViewController.selectSpan(span)
    }

    reloadTraces()
  }

  func updateTracesDirectoryURL(_ url: URL) {
    tracesDirectoryURL = url
    loader = TraceLoader(locator: TraceFileLocator(tracesDirectoryURL: url))
    reloadTraces()
  }

  func reloadTraces() {
    do {
      traces = try loader.loadTraces()
    } catch {
      traces = []
      selectedTrace = nil
    }

    traceListViewController.updateTraces(traces)
    if let selectedTrace, let refreshedSelection = traceListViewController.trace(withID: selectedTrace.id) {
      selectTrace(refreshedSelection)
    } else if let trace = traceListViewController.firstTrace {
      selectTrace(trace)
    } else {
      clearSelection()
    }
  }

  func updateSearchQuery(_ query: String) {
    traceListViewController.updateSearchQuery(query)
    if let selectedTrace, let filteredSelection = traceListViewController.trace(withID: selectedTrace.id) {
      selectTrace(filteredSelection)
    } else if let trace = traceListViewController.firstTrace {
      selectTrace(trace)
    } else {
      clearSelection()
    }
  }

  private func selectTrace(_ trace: Trace) {
    selectedTrace = trace
    traceListViewController.selectTrace(trace)
    timelineViewController.updateTrace(trace)
    spanInspectorViewController.updateTrace(trace)
  }

  private func clearSelection() {
    selectedTrace = nil
    traceListViewController.clearSelection()
    timelineViewController.clearTrace()
    spanInspectorViewController.clearTrace()
  }
}
