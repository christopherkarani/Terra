import AppKit
import Foundation
import SwiftUI
import TerraTraceKit

/// A table rendering span events with timestamps and attributes.
struct SpanEventsTable: View {
    let items: [EventItem]
    let maxRows: Int

    @State private var showAll = false

    init(items: [EventItem], maxRows: Int = AppSettings.spanEventsRowLimit) {
        self.items = items
        self.maxRows = max(1, maxRows)
    }

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView(
                "No Events",
                systemImage: "clock.badge.exclamationmark",
                description: Text("This span has no events")
            )
        } else {
            VStack(spacing: 8) {
                Table(visibleItems) {
                    TableColumn("Name") { item in
                        Text(item.name)
                            .font(DashboardTheme.detail)
                    }
                    .width(min: 120, ideal: 200)

                    TableColumn("Timestamp") { item in
                        Text(TraceFormatter.timestamp(item.timestamp))
                            .font(DashboardTheme.detail.monospaced())
                    }
                    .width(min: 80, ideal: 160)

                    TableColumn("Attributes") { item in
                        Text(item.attributesText)
                            .font(DashboardTheme.detail.monospaced())
                            .lineLimit(1)
                    }
                    .width(min: 80, ideal: 240)
                }

                if items.count > maxRows {
                    HStack {
                        Text("Showing \(visibleItems.count) of \(items.count) events")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                        Button(showAll ? "Show fewer" : "Show all") {
                            showAll.toggle()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        Button("Copy events JSON") {
                            copyEventsJSON(items)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var visibleItems: ArraySlice<EventItem> {
        if showAll || items.count <= maxRows {
            return items[items.startIndex..<items.endIndex]
        }
        return items[items.startIndex..<items.index(items.startIndex, offsetBy: maxRows)]
    }

    private func copyEventsJSON(_ sourceItems: [EventItem]) {
        let payload = sourceItems.map { item in
            [
                "name": item.name,
                "timestamp": ISO8601DateFormatter().string(from: item.timestamp),
                "attributes": Dictionary(uniqueKeysWithValues: item.attributes.map { ($0.0, $0.1) })
            ] as [String: Any]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
              let string = String(data: data, encoding: .utf8)
        else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
