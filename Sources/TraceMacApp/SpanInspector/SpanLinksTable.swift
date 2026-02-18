import SwiftUI
import TerraTraceKit
import OpenTelemetryApi

/// A two-column table displaying span links (trace ID and span ID).
struct SpanLinksTable: View {
    let items: [LinkItem]

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView(
                "No Links",
                systemImage: "link",
                description: Text("This span has no links")
            )
        } else {
            Table(items) {
                TableColumn("Trace ID") { item in
                    Text(item.traceId.hexString)
                        .font(DashboardTheme.detail.monospaced())
                        .lineLimit(1)
                }
                .width(min: 100, ideal: 220)

                TableColumn("Span ID") { item in
                    Text(item.spanId.hexString)
                        .font(DashboardTheme.detail.monospaced())
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 180)
            }
            .contextMenu(forSelectionType: LinkItem.self) { selection in
                if let item = selection.first {
                    Button("Copy Trace ID") {
                        copyToPasteboard(item.traceId.hexString)
                    }
                    Button("Copy Span ID") {
                        copyToPasteboard(item.spanId.hexString)
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
