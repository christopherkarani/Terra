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
  private var isLoading = false
  private var lastLoadFailureSignature: String?

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
    guard !isLoading else { return }
    isLoading = true

    let loader = self.loader
    Task.detached {
      let loadResult: Result<TraceLoadResult, Error>
      do {
        loadResult = .success(try loader.loadTracesWithFailures())
      } catch {
        loadResult = .failure(error)
      }

      await MainActor.run { [weak self] in
        guard let self else { return }
        self.isLoading = false

        switch loadResult {
        case .success(let loaded):
          self.traces = loaded.traces
          if loaded.traces.isEmpty {
            self.selectedTrace = nil
          }
          self.traceListViewController.updateTraces(self.traces)
          if let selectedTrace = self.selectedTrace,
             let refreshedSelection = self.traceListViewController.trace(withID: selectedTrace.id) {
            self.selectTrace(refreshedSelection)
          } else if let trace = self.traceListViewController.firstTrace {
            self.selectTrace(trace)
          } else {
            self.clearSelection()
          }
          self.presentTraceLoadFailuresIfNeeded(loaded.failures)

        case .failure(let error):
          self.traces = []
          self.clearSelection()
          self.traceListViewController.updateTraces([])
          self.presentTraceLoadError(error)
        }
      }
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

  private func presentTraceLoadFailuresIfNeeded(_ failures: [(file: URL, error: Error)]) {
    guard !failures.isEmpty else {
      lastLoadFailureSignature = nil
      return
    }

    let signature = failures
      .map { "\($0.file.lastPathComponent)|\(String(describing: type(of: $0.error)))" }
      .sorted()
      .joined(separator: ";")
    guard signature != lastLoadFailureSignature else { return }
    lastLoadFailureSignature = signature

    let preview = failures.prefix(3).map(\.file.lastPathComponent).joined(separator: ", ")
    let suffix = failures.count > 3 ? ", …" : ""
    Task {
      await AppLog.shared.error("trace.load_partial_failure count=\(failures.count) files=\(preview)\(suffix)")
    }

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Some trace files could not be loaded"
    alert.informativeText = "\(failures.count) file(s) failed to parse: \(preview)\(suffix)"
    alert.addButton(withTitle: "OK")
    if let window = view.window ?? NSApp.mainWindow {
      alert.beginSheetModal(for: window)
    } else {
      alert.runModal()
    }
  }

  private func presentTraceLoadError(_ error: Error) {
    Task { await AppLog.shared.error("trace.load_failed error=\(error)") }
    let alert = NSAlert(error: error)
    if let window = view.window ?? NSApp.mainWindow {
      alert.beginSheetModal(for: window)
    } else {
      alert.runModal()
    }
  }
}
