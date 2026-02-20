import AppKit

final class TraceToolbarProvider: NSObject, NSToolbarDelegate {
  var onSearchChange: ((String) -> Void)?
  var onReload: (() -> Void)?

  private lazy var searchItem: NSSearchToolbarItem = {
    let item = NSSearchToolbarItem(itemIdentifier: .traceSearch)
    item.searchField.placeholderString = "Filter traces"
    item.searchField.controlSize = .small
    item.searchField.target = self
    item.searchField.action = #selector(handleSearchChange)
    return item
  }()

  private lazy var reloadItem: NSToolbarItem = {
    let item = NSToolbarItem(itemIdentifier: .traceReload)
    item.label = "Reload"
    item.toolTip = "Reload traces"
    item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload")
    item.target = self
    item.action = #selector(handleReload)
    return item
  }()

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.traceSearch, .flexibleSpace, .traceReload]
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.traceSearch, .flexibleSpace, .traceReload]
  }

  func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
    switch itemIdentifier {
    case .traceSearch:
      return searchItem
    case .traceReload:
      return reloadItem
    default:
      return nil
    }
  }

  @objc private func handleSearchChange() {
    onSearchChange?(searchItem.searchField.stringValue)
  }

  @objc private func handleReload() {
    onReload?()
  }
}

extension NSToolbarItem.Identifier {
  static let traceSearch = NSToolbarItem.Identifier("TraceSearch")
  static let traceReload = NSToolbarItem.Identifier("TraceReload")
}
