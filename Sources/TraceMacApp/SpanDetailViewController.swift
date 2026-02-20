import AppKit
import OpenTelemetrySdk
import TerraTraceKit

final class SpanDetailViewController: NSViewController {
  private let headerLabel = NSTextField(labelWithString: "Details")
  private let subtitleLabel = NSTextField(labelWithString: "")
  private let tabView = NSTabView()

  private let attributesTable = NSTableView()
  private let eventsTable = NSTableView()
  private let lifecycleEventsTable = NSTableView()
  private let policyEventsTable = NSTableView()
  private let recommendationEventsTable = NSTableView()
  private let anomalyEventsTable = NSTableView()
  private let hardwareEventsTable = NSTableView()
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
    configure(
      table: eventsTable,
      columns: [("Event", 140), ("Timestamp", 125), ("Attributes", 220)]
    )
    configure(
      table: lifecycleEventsTable,
      columns: [("Event", 140), ("Timestamp", 125), ("Attributes", 220)]
    )
    configure(
      table: policyEventsTable,
      columns: [("Event", 140), ("Timestamp", 125), ("Attributes", 220)]
    )
    configure(
      table: recommendationEventsTable,
      columns: [("Event", 140), ("Timestamp", 125), ("Attributes", 220)]
    )
    configure(
      table: anomalyEventsTable,
      columns: [("Event", 140), ("Timestamp", 125), ("Attributes", 220)]
    )
    configure(
      table: hardwareEventsTable,
      columns: [("Event", 140), ("Timestamp", 125), ("Attributes", 220)]
    )
    configure(table: linksTable, columns: [("Trace ID", 220), ("Span ID", 180)])

    let attributesItem = NSTabViewItem(identifier: "attributes")
    attributesItem.label = "Attributes"
    attributesItem.view = wrap(table: attributesTable)

    let eventsItem = NSTabViewItem(identifier: "events")
    eventsItem.label = "Events"
    eventsItem.view = wrap(table: eventsTable)

    let lifecycleItem = NSTabViewItem(identifier: "lifecycle")
    lifecycleItem.label = "Lifecycle"
    lifecycleItem.view = wrap(table: lifecycleEventsTable)

    let policyItem = NSTabViewItem(identifier: "policy")
    policyItem.label = "Policy"
    policyItem.view = wrap(table: policyEventsTable)

    let recommendationItem = NSTabViewItem(identifier: "recommendations")
    recommendationItem.label = "Recommendations"
    recommendationItem.view = wrap(table: recommendationEventsTable)

    let anomalyItem = NSTabViewItem(identifier: "anomalies")
    anomalyItem.label = "Anomalies"
    anomalyItem.view = wrap(table: anomalyEventsTable)

    let hardwareItem = NSTabViewItem(identifier: "hardware")
    hardwareItem.label = "Hardware"
    hardwareItem.view = wrap(table: hardwareEventsTable)

    let linksItem = NSTabViewItem(identifier: "links")
    linksItem.label = "Links"
    linksItem.view = wrap(table: linksTable)

    tabView.addTabViewItem(attributesItem)
    tabView.addTabViewItem(eventsItem)
    tabView.addTabViewItem(lifecycleItem)
    tabView.addTabViewItem(policyItem)
    tabView.addTabViewItem(recommendationItem)
    tabView.addTabViewItem(anomalyItem)
    tabView.addTabViewItem(hardwareItem)
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
    lifecycleEventsTable.reloadData()
    policyEventsTable.reloadData()
    recommendationEventsTable.reloadData()
    anomalyEventsTable.reloadData()
    hardwareEventsTable.reloadData()
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
      return limitedEventItems(viewModel.eventItems).count
    case lifecycleEventsTable:
      return limitedEventItems(viewModel.lifecycleEventItems).count
    case policyEventsTable:
      return limitedEventItems(viewModel.policyEventItems).count
    case recommendationEventsTable:
      return limitedEventItems(viewModel.recommendationEventItems).count
    case anomalyEventsTable:
      return limitedEventItems(viewModel.anomalyEventItems).count
    case hardwareEventsTable:
      return limitedEventItems(viewModel.hardwareEventItems).count
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
      let item = limitedEventItems(viewModel.eventItems)[row]
      value = cellValue(for: item, tableColumn: tableColumn)
    } else if tableView == lifecycleEventsTable {
      let item = limitedEventItems(viewModel.lifecycleEventItems)[row]
      value = cellValue(for: item, tableColumn: tableColumn)
    } else if tableView == policyEventsTable {
      let item = limitedEventItems(viewModel.policyEventItems)[row]
      value = cellValue(for: item, tableColumn: tableColumn)
    } else if tableView == recommendationEventsTable {
      let item = limitedEventItems(viewModel.recommendationEventItems)[row]
      value = cellValue(for: item, tableColumn: tableColumn)
    } else if tableView == anomalyEventsTable {
      let item = limitedEventItems(viewModel.anomalyEventItems)[row]
      value = cellValue(for: item, tableColumn: tableColumn)
    } else if tableView == hardwareEventsTable {
      let item = limitedEventItems(viewModel.hardwareEventItems)[row]
      value = cellValue(for: item, tableColumn: tableColumn)
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

  private func cellValue(
    for item: EventItem,
    tableColumn: NSTableColumn?
  ) -> String {
    guard let identifier = tableColumn?.identifier.rawValue else { return "" }
    switch identifier {
    case "Event":
      return item.name
    case "Timestamp":
      return TraceFormatter.timestamp(item.timestamp)
    case "Attributes":
      return item.attributesText
    default:
      return ""
    }
  }

  private func limitedEventItems(_ items: [EventItem]) -> [EventItem] {
    let limit = max(1, AppSettings.spanEventsRowLimit)
    if items.count <= limit {
      return items
    }
    return Array(items.prefix(limit))
  }
}
