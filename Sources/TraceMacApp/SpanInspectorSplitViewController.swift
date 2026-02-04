import AppKit
import TerraTraceKit

@MainActor
final class SpanInspectorSplitViewController: NSSplitViewController {
  let spanListViewController = SpanListViewController()
  let detailViewController = SpanDetailViewController()

  override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
    super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
  }

  required init?(coder: NSCoder) {
    return nil
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    configureSplitView()
  }

  func update(
    snapshot: TraceSnapshot,
    selectedTraceID: TraceID?,
    selectedSpanID: SpanID?,
    spans: [SpanRecord]
  ) {
    spanListViewController.apply(spans: spans, selectedSpanID: selectedSpanID)
    detailViewController.update(
      snapshot: snapshot,
      selectedTraceID: selectedTraceID,
      selectedSpanID: selectedSpanID
    )
  }

  private func configureSplitView() {
    splitView.isVertical = false
    splitView.dividerStyle = .thin

    let listItem = NSSplitViewItem(viewController: spanListViewController)
    listItem.minimumThickness = 160
    listItem.canCollapse = false

    let detailItem = NSSplitViewItem(viewController: detailViewController)
    detailItem.minimumThickness = 200
    detailItem.canCollapse = false

    addSplitViewItem(listItem)
    addSplitViewItem(detailItem)
  }
}
