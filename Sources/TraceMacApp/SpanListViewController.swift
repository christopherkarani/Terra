import AppKit
import TerraTraceKit

@MainActor
protocol SpanListViewControllerDelegate: AnyObject {
  func spanListViewController(_ controller: SpanListViewController, didSelectSpanID spanID: SpanID?)
}

@MainActor
final class SpanListViewController: NSViewController {
  weak var delegate: SpanListViewControllerDelegate?

  private let scrollView = NSScrollView()
  private let tableView = NSTableView()
  private let emptyTitleLabel = NSTextField(labelWithString: "No spans yet")
  private let emptySubtitleLabel = NSTextField(labelWithString: "Select a trace to see spans")
  private let emptyStack = NSStackView()

  private let cellIdentifier = NSUserInterfaceItemIdentifier("SpanCell")
  private var spans: [SpanRecord] = []
  private var isApplyingSnapshot = false
  private let statusIndicatorIdentifier = NSUserInterfaceItemIdentifier("SpanStatusIndicator")

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

  func apply(spans: [SpanRecord], selectedSpanID: SpanID?) {
    isApplyingSnapshot = true
    self.spans = spans
    tableView.reloadData()

    if let selectedSpanID, let index = spans.firstIndex(where: { $0.spanID == selectedSpanID }) {
      tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
      tableView.scrollRowToVisible(index)
    } else {
      tableView.deselectAll(nil)
    }

    updateEmptyState()
    isApplyingSnapshot = false
  }

  private func configureTableView() {
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SpanColumn"))
    column.title = "Span"
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
    tableView.setAccessibilityLabel("Spans")

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
    let isEmpty = spans.isEmpty
    emptyStack.isHidden = !isEmpty
    scrollView.isHidden = isEmpty
    tableView.setAccessibilityHidden(isEmpty)
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
extension SpanListViewController: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in tableView: NSTableView) -> Int {
    spans.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard row < spans.count else { return nil }

    let span = spans[row]
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
      statusIndicator.setAccessibilityLabel("Span status")

      let textField = NSTextField(labelWithString: "")
      textField.translatesAutoresizingMaskIntoConstraints = false
      textField.font = TraceUIStyle.Typography.body
      textField.textColor = TraceUIStyle.Colors.primaryText
      textField.lineBreakMode = .byTruncatingTail

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

    let statusText = Self.statusAccessibilityValue(for: span.status)
    cell.textField?.stringValue = "\(span.name) (\(statusText))"
    cell.textField?.toolTip = span.spanID.hex
    if let statusIndicator = cell.subviews.first(where: { $0.identifier == statusIndicatorIdentifier }) {
      statusIndicator.layer?.backgroundColor = TraceUIStyle.Colors.status(span.status).cgColor
      statusIndicator.setAccessibilityValue(Self.statusAccessibilityValue(for: span.status))
    }
    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !isApplyingSnapshot else { return }
    let row = tableView.selectedRow
    if row >= 0 && row < spans.count {
      delegate?.spanListViewController(self, didSelectSpanID: spans[row].spanID)
    } else {
      delegate?.spanListViewController(self, didSelectSpanID: nil)
    }
  }
}
