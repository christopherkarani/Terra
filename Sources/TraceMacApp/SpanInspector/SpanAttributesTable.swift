import SwiftUI
import TerraTraceKit

/// A two-column table displaying span attribute key-value pairs.
struct SpanAttributesTable: View {
    let items: [AttributeItem]

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView(
                "No Attributes",
                systemImage: "list.bullet",
                description: Text("This span has no attributes")
            )
        } else {
            Table(items) {
                TableColumn("Key") { item in
                    Text(item.key)
                        .font(DashboardTheme.detail)
                }
                .width(min: 80, ideal: 160)

                TableColumn("Value") { item in
                    Text(item.value)
                        .font(DashboardTheme.detail.monospaced())
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 240)
            }
            .contextMenu(forSelectionType: AttributeItem.self) { selection in
                if let item = selection.first {
                    Button("Copy Key") {
                        copyToPasteboard(item.key)
                    }
                    Button("Copy Value") {
                        copyToPasteboard(item.value)
                    }
                    Divider()
                    Button("Copy Key=Value") {
                        copyToPasteboard("\(item.key)=\(item.value)")
                    }
                }
            }
        }
    }
}

private func copyToPasteboard(_ string: String) {
    #if canImport(AppKit)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
    #endif
}
