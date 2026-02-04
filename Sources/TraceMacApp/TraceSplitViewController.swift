import AppKit
import TerraTraceKit

@MainActor
final class TraceSplitViewController: NSSplitViewController {
  private let viewModel: TraceViewModel
  private let listViewController = TraceListViewController()
  private let timelineViewController = TraceTimelineViewController()
  private let detailViewController = SpanDetailViewController()
  private let loadingOverlay = ClickThroughView()
  private let loadingIndicator = NSProgressIndicator()
  private let loadingLabel = NSTextField(labelWithString: "Refreshing traces…")
  private let loadingStack = NSStackView()

  private var refreshTimer: Timer?
  private var isRefreshing = false
  private var isLoading = false

  init(viewModel: TraceViewModel) {
    self.viewModel = viewModel
    super.init(nibName: nil, bundle: nil)
    listViewController.delegate = self
  }

  required init?(coder: NSCoder) {
    return nil
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    configureSplitView()
    configureLoadingOverlay()
    applySnapshot()
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    startRefreshLoop()
  }

  override func viewWillDisappear() {
    super.viewWillDisappear()
    stopRefreshLoop()
  }

  private func configureSplitView() {
    splitView.isVertical = true
    splitView.dividerStyle = .thin

    let listItem = NSSplitViewItem(viewController: listViewController)
    listItem.minimumThickness = 200
    listItem.canCollapse = false

    let timelineItem = NSSplitViewItem(viewController: timelineViewController)

    let detailItem = NSSplitViewItem(viewController: detailViewController)
    detailItem.minimumThickness = 240
    detailItem.canCollapse = false

    addSplitViewItem(listItem)
    addSplitViewItem(timelineItem)
    addSplitViewItem(detailItem)
  }

  private func startRefreshLoop() {
    guard refreshTimer == nil else { return }
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.refreshSnapshot()
      }
    }
    refreshSnapshot()
  }

  private func stopRefreshLoop() {
    refreshTimer?.invalidate()
    refreshTimer = nil
    setLoading(false)
  }

  private func refreshSnapshot() {
    guard !isRefreshing else { return }
    isRefreshing = true
    setLoading(true)

    Task { [weak self] in
      guard let self else { return }
      await self.viewModel.refresh()
      await MainActor.run {
        self.applySnapshot()
        self.isRefreshing = false
        self.setLoading(false)
      }
    }
  }

  private func applySnapshot() {
    let snapshot = viewModel.snapshot
    listViewController.apply(snapshot: snapshot, selectedTraceID: viewModel.selectedTraceID)
    updateDetailViews(snapshot: snapshot)
  }

  private func updateDetailViews(snapshot: TraceSnapshot) {
    let selectedTraceID = viewModel.selectedTraceID
    let spans = selectedTraceID.flatMap { snapshot.traces[$0] }
    timelineViewController.update(selectedTraceID: selectedTraceID, spans: spans)
    detailViewController.update(
      snapshot: snapshot,
      selectedTraceID: selectedTraceID,
      selectedSpanID: viewModel.selectedSpanID
    )
  }

  private func configureLoadingOverlay() {
    loadingOverlay.translatesAutoresizingMaskIntoConstraints = false
    loadingOverlay.wantsLayer = true
    loadingOverlay.layer?.backgroundColor = TraceUIStyle.Colors.loadingBackdrop.cgColor
    loadingOverlay.alphaValue = 0
    loadingOverlay.isHidden = true

    loadingIndicator.style = .spinning
    loadingIndicator.controlSize = .small
    loadingIndicator.isIndeterminate = true
    loadingIndicator.startAnimation(nil)

    loadingLabel.font = TraceUIStyle.Typography.subtitle
    loadingLabel.textColor = TraceUIStyle.Colors.secondaryText

    loadingStack.orientation = .horizontal
    loadingStack.spacing = TraceUIStyle.Spacing.small
    loadingStack.alignment = .centerY
    loadingStack.translatesAutoresizingMaskIntoConstraints = false
    loadingStack.addArrangedSubview(loadingIndicator)
    loadingStack.addArrangedSubview(loadingLabel)

    view.addSubview(loadingOverlay)
    loadingOverlay.addSubview(loadingStack)

    NSLayoutConstraint.activate([
      loadingOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      loadingOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      loadingOverlay.topAnchor.constraint(equalTo: view.topAnchor),
      loadingOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      loadingStack.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
      loadingStack.topAnchor.constraint(equalTo: loadingOverlay.topAnchor, constant: TraceUIStyle.Spacing.large)
    ])
  }

  private func setLoading(_ isLoading: Bool) {
    guard isLoading != self.isLoading else { return }
    self.isLoading = isLoading

    loadingOverlay.isHidden = false
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.15
      loadingOverlay.animator().alphaValue = isLoading ? 1 : 0
    }
  }
}

@MainActor
extension TraceSplitViewController: TraceListViewControllerDelegate {
  func traceListViewController(_ controller: TraceListViewController, didSelectTraceID traceID: TraceID?) {
    viewModel.selectedTraceID = traceID
    updateDetailViews(snapshot: viewModel.snapshot)
  }
}

private final class ClickThroughView: NSView {
  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }
}
