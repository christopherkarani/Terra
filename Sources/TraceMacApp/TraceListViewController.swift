import AppKit
import TerraTraceKit

final class TraceListViewController: NSViewController {
  var onSelectTrace: ((Trace) -> Void)?

  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private let headerLabel = NSTextField(labelWithString: "Traces")
  private var viewModel = TraceListViewModel(traces: [])
  private var isProgrammaticSelection = false

  var firstTrace: Trace? {
    viewModel.filteredTraces.first
  }

  override func loadView() {
    view = NSView()

    TraceUI.styleSectionHeader(headerLabel)

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TraceColumn"))
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)
    TraceUI.styleTable(tableView, rowHeight: 40)
    tableView.delegate = self
    tableView.dataSource = self

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    TraceUI.styleSurface(scrollView)

    let stack = NSStackView(views: [headerLabel, scrollView])
    stack.orientation = .vertical
    stack.spacing = TraceUI.sectionSpacing
    stack.edgeInsets = TraceUI.contentInsets
    stack.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      stack.topAnchor.constraint(equalTo: view.topAnchor),
      stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
  }

  func updateTraces(_ traces: [Trace]) {
    viewModel.updateTraces(traces)
    updateHeader()
    tableView.reloadData()
  }

  func updateSearchQuery(_ query: String) {
    viewModel.searchQuery = query
    updateHeader()
    tableView.reloadData()
  }

  private func updateHeader() {
    headerLabel.stringValue = "Traces (\(viewModel.filteredTraces.count))"
  }

  func trace(withID id: String) -> Trace? {
    viewModel.filteredTraces.first { $0.id == id }
  }

  func selectTrace(_ trace: Trace) {
    guard let row = viewModel.filteredTraces.firstIndex(where: { $0.id == trace.id }) else {
      clearSelection()
      return
    }

    viewModel.selectTrace(id: trace.id)
    isProgrammaticSelection = true
    tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    tableView.scrollRowToVisible(row)
    isProgrammaticSelection = false
  }

  func clearSelection() {
    isProgrammaticSelection = true
    tableView.deselectAll(nil)
    isProgrammaticSelection = false
  }
}

extension TraceListViewController: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in tableView: NSTableView) -> Int {
    viewModel.filteredTraces.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let trace = viewModel.filteredTraces[row]
    let identifier = NSUserInterfaceItemIdentifier("TraceCell")

    let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
      ?? NSTableCellView()
    cell.identifier = identifier

    let textField: NSTextField
    if let existing = cell.textField {
      textField = existing
    } else {
      textField = NSTextField(labelWithString: "")
      textField.translatesAutoresizingMaskIntoConstraints = false
      textField.lineBreakMode = .byTruncatingTail
      cell.addSubview(textField)
      cell.textField = textField
      NSLayoutConstraint.activate([
        textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
        textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
        textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
      ])
    }

    let duration = TraceFormatter.duration(trace.duration)
    let titleColor: NSColor = trace.hasError ? .systemRed : .labelColor
    let attributed = NSMutableAttributedString(
      string: trace.displayName,
      attributes: [
        .font: TraceUI.rowTitleFont,
        .foregroundColor: titleColor
      ]
    )
    attributed.append(
      NSAttributedString(
        string: "  \(duration)",
        attributes: [
          .font: TraceUI.rowMetaFont,
          .foregroundColor: NSColor.secondaryLabelColor
        ]
      )
    )
    textField.attributedStringValue = attributed

    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    let row = tableView.selectedRow
    guard row >= 0, row < viewModel.filteredTraces.count else { return }
    let trace = viewModel.filteredTraces[row]
    viewModel.selectTrace(id: trace.id)
    if !isProgrammaticSelection {
      onSelectTrace?(trace)
    }
  }
}
