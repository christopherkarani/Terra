import SwiftUI
import TerraTraceKit

/// A two-column table displaying span events with their timestamps.
struct SpanEventsTable: View {
    let items: [EventItem]

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView(
                "No Events",
                systemImage: "clock.badge.exclamationmark",
                description: Text("This span has no events")
            )
        } else {
            Table(items) {
                TableColumn("Name") { item in
                    Text(item.name)
                        .font(DashboardTheme.detail)
                }
                .width(min: 100, ideal: 200)

                TableColumn("Timestamp") { item in
                    Text(TraceFormatter.timestamp(item.timestamp))
                        .font(DashboardTheme.detail.monospaced())
                }
                .width(min: 80, ideal: 200)
            }
        }
    }
}
