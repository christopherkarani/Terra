import AppKit
import OpenTelemetrySdk
import TerraTraceKit

final class SpanInspectorSplitViewController: NSSplitViewController {
  var onSelectSpan: ((SpanData) -> Void)?

  private let spanListViewController = SpanListViewController()
  private let spanDetailViewController = SpanDetailViewController()

  override func viewDidLoad() {
    super.viewDidLoad()

    splitView.isVertical = false
    splitView.dividerStyle = .paneSplitter

    let listItem = NSSplitViewItem(viewController: spanListViewController)
    listItem.minimumThickness = 180
    listItem.preferredThicknessFraction = 0.42
    let detailItem = NSSplitViewItem(viewController: spanDetailViewController)
    detailItem.minimumThickness = 180

    addSplitViewItem(listItem)
    addSplitViewItem(detailItem)

    spanListViewController.onSelectSpan = { [weak self] span in
      self?.spanDetailViewController.updateSpan(span)
      self?.onSelectSpan?(span)
    }
  }

  func updateTrace(_ trace: Trace) {
    spanListViewController.updateTrace(trace)
    spanDetailViewController.clear()
  }

  func clearTrace() {
    spanListViewController.clear()
    spanDetailViewController.clear()
  }

  func selectSpan(_ span: SpanData) {
    spanDetailViewController.updateSpan(span)
  }

  func selectSpanInList(_ span: SpanData) {
    spanListViewController.selectSpan(span)
  }
}
