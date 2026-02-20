import AppKit
import OpenTelemetrySdk
import TerraTraceKit

final class SpanDetailViewController: NSViewController {
  private let headerLabel = NSTextField(labelWithString: "Details")
  private let subtitleLabel = NSTextField(labelWithString: "")
  private let tabView = NSTabView()

  private let attributesTable = NSTableView()
  private let eventsTable = NSTableView()
  private let linksTable = NSTableView()

  private let viewModel = SpanDetailViewModel()

  override func loadView() {
    view = NSView()

    TraceUI.styleSectionHeader(headerLabel)
    TraceUI.styleSubtitle(subtitleLabel)

    let headerStack = NSStackView(views: [headerLabel, subtitleLabel])
    headerStack.orientation = .vertical
    headerStack.spacing = 3

    configure(table: attributesTable, columns: [("Key", 160), ("Value", 240)])
    configure(table: eventsTable, columns: [("Event", 200), ("Timestamp", 200)])
    configure(table: linksTable, columns: [("Trace ID", 220), ("Span ID", 180)])

    let attributesItem = NSTabViewItem(identifier: "attributes")
    attributesItem.label = "Attributes"
    attributesItem.view = wrap(table: attributesTable)

    let eventsItem = NSTabViewItem(identifier: "events")
    eventsItem.label = "Events"
    eventsItem.view = wrap(table: eventsTable)

    let linksItem = NSTabViewItem(identifier: "links")
    linksItem.label = "Links"
    linksItem.view = wrap(table: linksTable)

    tabView.addTabViewItem(attributesItem)
    tabView.addTabViewItem(eventsItem)
    tabView.addTabViewItem(linksItem)

    let stack = NSStackView(views: [headerStack, tabView])
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

  func updateSpan(_ span: SpanData) {
    viewModel.select(span: span)
    let duration = TraceFormatter.duration(span.endTime.timeIntervalSince(span.startTime))
    subtitleLabel.stringValue = "\(span.name)  •  \(duration)  •  \(span.status.name.uppercased())"
    reloadTables()
  }

  func clear() {
    viewModel.clearSelection()
    headerLabel.stringValue = "Details"
    subtitleLabel.stringValue = ""
    reloadTables()
  }

  private func reloadTables() {
    attributesTable.reloadData()
    eventsTable.reloadData()
    linksTable.reloadData()
  }

  private func configure(table: NSTableView, columns: [(String, CGFloat)]) {
    TraceUI.styleTable(table, rowHeight: 26)
    table.delegate = self
    table.dataSource = self

    for (title, width) in columns {
      let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(title))
      column.title = title
      column.width = width
      table.addTableColumn(column)
    }
  }

  private func wrap(table: NSTableView) -> NSView {
    let scroll = NSScrollView()
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    scroll.borderType = .noBorder
    TraceUI.styleSurface(scroll)
    return scroll
  }
}

extension SpanDetailViewController: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in tableView: NSTableView) -> Int {
    switch tableView {
    case attributesTable:
      return viewModel.attributeItems.count
    case eventsTable:
      return viewModel.eventItems.count
    case linksTable:
      return viewModel.linkItems.count
    default:
      return 0
    }
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let identifier = NSUserInterfaceItemIdentifier("Cell")
    let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
      ?? NSTableCellView()
    cell.identifier = identifier

    let textField: NSTextField
    if let existing = cell.textField {
      textField = existing
    } else {
      textField = NSTextField(labelWithString: "")
      textField.translatesAutoresizingMaskIntoConstraints = false
      textField.lineBreakMode = .byTruncatingMiddle
      cell.addSubview(textField)
      cell.textField = textField
      NSLayoutConstraint.activate([
        textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
        textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
        textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
      ])
    }

    let value: String
    if tableView == attributesTable {
      let item = viewModel.attributeItems[row]
      value = tableColumn?.identifier.rawValue == "Key" ? item.key : item.value
    } else if tableView == eventsTable {
      let item = viewModel.eventItems[row]
      value = tableColumn?.identifier.rawValue == "Event" ? item.name : TraceFormatter.timestamp(item.timestamp)
    } else if tableView == linksTable {
      let item = viewModel.linkItems[row]
      value = tableColumn?.identifier.rawValue == "Trace ID" ? item.traceId.hexString : item.spanId.hexString
    } else {
      value = ""
    }

    textField.stringValue = value
    textField.font = TraceUI.detailFont
    textField.textColor = .labelColor

    return cell
  }
}
