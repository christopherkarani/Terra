import AppKit

@MainActor
final class TraceToolbarProvider: NSObject, NSToolbarDelegate {
  enum ItemIdentifier {
    static let search = NSToolbarItem.Identifier("trace.search")
    static let filter = NSToolbarItem.Identifier("trace.filter")
    static let options = NSToolbarItem.Identifier("trace.options")
  }

  let toolbar: NSToolbar

  override init() {
    self.toolbar = NSToolbar(identifier: "TraceToolbar")
    super.init()
    toolbar.displayMode = .iconAndLabel
    toolbar.allowsUserCustomization = false
    toolbar.delegate = self
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [
      ItemIdentifier.search,
      ItemIdentifier.filter,
      ItemIdentifier.options,
      .flexibleSpace
    ]
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [
      ItemIdentifier.search,
      .flexibleSpace,
      ItemIdentifier.filter,
      ItemIdentifier.options
    ]
  }

  func toolbar(
    _ toolbar: NSToolbar,
    itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    switch itemIdentifier {
    case ItemIdentifier.search:
      let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
      item.searchField.placeholderString = "Search traces"
      return item
    case ItemIdentifier.filter:
      return makeButtonItem(identifier: itemIdentifier, title: "Filter")
    case ItemIdentifier.options:
      return makeButtonItem(identifier: itemIdentifier, title: "Options")
    default:
      return nil
    }
  }

  private func makeButtonItem(identifier: NSToolbarItem.Identifier, title: String) -> NSToolbarItem {
    let item = NSToolbarItem(itemIdentifier: identifier)
    let button = NSButton(title: title, target: self, action: #selector(toolbarPlaceholderAction(_:)))
    button.bezelStyle = .texturedRounded
    item.label = title
    item.view = button
    return item
  }

  @objc
  private func toolbarPlaceholderAction(_ sender: Any?) {
    // Placeholder for future toolbar actions.
  }
}
