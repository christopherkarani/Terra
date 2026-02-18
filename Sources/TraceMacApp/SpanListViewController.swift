import AppKit
import OpenTelemetryApi
import OpenTelemetrySdk
import TerraTraceKit

final class SpanListViewController: NSViewController {
  var onSelectSpan: ((SpanData) -> Void)?

  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private let headerLabel = NSTextField(labelWithString: "Spans")
  private var rows: [SpanRow] = []
  private var isProgrammaticSelection = false

  override func loadView() {
    view = NSView()

    TraceUI.styleSectionHeader(headerLabel)

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SpanColumn"))
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)
    TraceUI.styleTable(tableView, rowHeight: 34)
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

  func updateTrace(_ trace: Trace) {
    rows = SpanRowBuilder.buildRows(spans: trace.orderedSpans)
    updateHeader()
    tableView.reloadData()
  }

  func clear() {
    rows = []
    updateHeader()
    tableView.reloadData()
  }

  private func updateHeader() {
    headerLabel.stringValue = "Spans (\(rows.count))"
  }

  func selectSpan(_ span: SpanData) {
    if let index = rows.firstIndex(where: { $0.span.spanId == span.spanId }) {
      isProgrammaticSelection = true
      tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
      tableView.scrollRowToVisible(index)
      isProgrammaticSelection = false
    }
  }
}

extension SpanListViewController: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in tableView: NSTableView) -> Int {
    rows.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let rowItem = rows[row]
    let identifier = NSUserInterfaceItemIdentifier("SpanCell")

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

    let duration = TraceFormatter.duration(rowItem.span.endTime.timeIntervalSince(rowItem.span.startTime))
    let indent = String(repeating: "  ", count: rowItem.depth)
    let titleColor: NSColor = rowItem.span.status.isError ? .systemRed : .labelColor
    let attributed = NSMutableAttributedString(
      string: "\(indent)\(rowItem.span.name)",
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
    guard row >= 0, row < rows.count else { return }
    if !isProgrammaticSelection {
      onSelectSpan?(rows[row].span)
    }
  }
}

private struct SpanRow {
  let span: SpanData
  let depth: Int
}

private enum SpanRowBuilder {
  static func buildRows(spans: [SpanData]) -> [SpanRow] {
    let spanIds = Set(spans.map { $0.spanId })
    var childrenByParent: [SpanId?: [SpanData]] = Dictionary(grouping: spans, by: { $0.parentSpanId })

    let roots = spans.filter { span in
      guard let parent = span.parentSpanId else { return true }
      return !spanIds.contains(parent)
    }.sorted { $0.startTime < $1.startTime }

    var rows: [SpanRow] = []
    for root in roots {
      append(span: root, depth: 0, childrenByParent: &childrenByParent, rows: &rows)
    }

    return rows
  }

  private static func append(span: SpanData, depth: Int, childrenByParent: inout [SpanId?: [SpanData]], rows: inout [SpanRow]) {
    rows.append(SpanRow(span: span, depth: depth))
    let children = (childrenByParent[span.spanId] ?? []).sorted { $0.startTime < $1.startTime }
    for child in children {
      append(span: child, depth: depth + 1, childrenByParent: &childrenByParent, rows: &rows)
    }
  }
}
