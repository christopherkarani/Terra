import AppKit
import TerraTraceKit

@MainActor
protocol TraceListViewControllerDelegate: AnyObject {
  func traceListViewController(_ controller: TraceListViewController, didSelectTraceID traceID: TraceID?)
}

@MainActor
final class TraceListViewController: NSViewController {
  weak var delegate: TraceListViewControllerDelegate?

  private let scrollView = NSScrollView()
  private let tableView = NSTableView()
  private let emptyTitleLabel = NSTextField(labelWithString: "No traces yet")
  private let emptySubtitleLabel = NSTextField(labelWithString: "Waiting for incoming spans")
  private let emptyStack = NSStackView()

  private let cellIdentifier = NSUserInterfaceItemIdentifier("TraceCell")
  private var traceIDs: [TraceID] = []
  private var traceStatusByID: [TraceID: StatusCode] = [:]
  private var isApplyingSnapshot = false
  private let statusIndicatorIdentifier = NSUserInterfaceItemIdentifier("TraceStatusIndicator")

  override func loadView() {
    view = NSView()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    configureTableView()
    configureLayout()
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    view.window?.makeFirstResponder(tableView)
  }

  func apply(snapshot: TraceSnapshot, selectedTraceID: TraceID?) {
    isApplyingSnapshot = true
    traceIDs = snapshot.traces.keys.sorted()
    traceStatusByID = snapshot.traces.reduce(into: [:]) { result, entry in
      result[entry.key] = Self.traceStatus(for: entry.value)
    }
    tableView.reloadData()

    if let selectedTraceID, let index = traceIDs.firstIndex(of: selectedTraceID) {
      tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    } else {
      tableView.deselectAll(nil)
    }

    updateEmptyState()
    isApplyingSnapshot = false
  }

  private func configureTableView() {
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TraceColumn"))
    column.title = "Trace"
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.rowHeight = TraceUIStyle.Sizing.listRowHeight
    tableView.intercellSpacing = NSSize(width: 0, height: TraceUIStyle.Spacing.xSmall)
    tableView.backgroundColor = TraceUIStyle.Colors.listBackground
    tableView.usesAlternatingRowBackgroundColors = false
    tableView.allowsMultipleSelection = false
    tableView.delegate = self
    tableView.dataSource = self
    tableView.setAccessibilityLabel("Traces")
  }

  private func configureLayout() {
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.hasVerticalScroller = true
    scrollView.documentView = tableView
    scrollView.drawsBackground = true
    scrollView.backgroundColor = TraceUIStyle.Colors.listBackground

    emptyTitleLabel.font = TraceUIStyle.Typography.emptyTitle
    emptyTitleLabel.textColor = TraceUIStyle.Colors.secondaryText
    emptyTitleLabel.alignment = .center

    emptySubtitleLabel.font = TraceUIStyle.Typography.emptySubtitle
    emptySubtitleLabel.textColor = TraceUIStyle.Colors.tertiaryText
    emptySubtitleLabel.alignment = .center

    emptyStack.orientation = .vertical
    emptyStack.spacing = TraceUIStyle.Spacing.xSmall
    emptyStack.alignment = .centerX
    emptyStack.translatesAutoresizingMaskIntoConstraints = false
    emptyStack.addArrangedSubview(emptyTitleLabel)
    emptyStack.addArrangedSubview(emptySubtitleLabel)

    view.addSubview(scrollView)
    view.addSubview(emptyStack)

    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: view.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      emptyStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      emptyStack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
    ])

    updateEmptyState()
  }

  private func updateEmptyState() {
    let isEmpty = traceIDs.isEmpty
    emptyStack.isHidden = !isEmpty
    scrollView.isHidden = isEmpty
    tableView.setAccessibilityHidden(isEmpty)
  }

  private static func traceStatus(for spans: [SpanRecord]) -> StatusCode {
    if spans.contains(where: { $0.status == .error }) {
      return .error
    }
    if spans.contains(where: { $0.status == .ok }) {
      return .ok
    }
    return .unset
  }

  private static func statusAccessibilityValue(for status: StatusCode) -> String {
    switch status {
    case .unset:
      return "Unset"
    case .ok:
      return "OK"
    case .error:
      return "Error"
    }
  }
}

@MainActor
extension TraceListViewController: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in tableView: NSTableView) -> Int {
    traceIDs.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard row < traceIDs.count else { return nil }

    let traceID = traceIDs[row]
    let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView
      ?? NSTableCellView()

    cell.identifier = cellIdentifier

    if cell.textField == nil {
      let statusIndicator = NSView()
      statusIndicator.translatesAutoresizingMaskIntoConstraints = false
      statusIndicator.wantsLayer = true
      statusIndicator.layer?.cornerRadius = TraceUIStyle.Sizing.listStatusDot / 2
      statusIndicator.identifier = statusIndicatorIdentifier
      statusIndicator.setAccessibilityElement(true)
      statusIndicator.setAccessibilityLabel("Trace status")

      let textField = NSTextField(labelWithString: "")
      textField.translatesAutoresizingMaskIntoConstraints = false
      textField.font = TraceUIStyle.Typography.mono
      textField.textColor = TraceUIStyle.Colors.primaryText
      textField.lineBreakMode = .byTruncatingMiddle

      cell.addSubview(statusIndicator)
      cell.addSubview(textField)
      cell.textField = textField
      NSLayoutConstraint.activate([
        statusIndicator.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: TraceUIStyle.Spacing.small),
        statusIndicator.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        statusIndicator.widthAnchor.constraint(equalToConstant: TraceUIStyle.Sizing.listStatusDot),
        statusIndicator.heightAnchor.constraint(equalTo: statusIndicator.widthAnchor),

        textField.leadingAnchor.constraint(equalTo: statusIndicator.trailingAnchor, constant: TraceUIStyle.Spacing.small),
        textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -TraceUIStyle.Spacing.small),
        textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
      ])
    }

    cell.textField?.stringValue = traceID.short
    cell.textField?.toolTip = traceID.hex
    if let statusIndicator = cell.subviews.first(where: { $0.identifier == statusIndicatorIdentifier }) {
      let status = traceStatusByID[traceID] ?? .unset
      statusIndicator.layer?.backgroundColor = TraceUIStyle.Colors.status(status).cgColor
      statusIndicator.setAccessibilityValue(Self.statusAccessibilityValue(for: status))
    }
    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !isApplyingSnapshot else { return }
    let row = tableView.selectedRow
    if row >= 0 && row < traceIDs.count {
      delegate?.traceListViewController(self, didSelectTraceID: traceIDs[row])
    } else {
      delegate?.traceListViewController(self, didSelectTraceID: nil)
    }
  }
}
