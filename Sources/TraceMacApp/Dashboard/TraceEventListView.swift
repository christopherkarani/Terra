import SwiftUI

struct TraceEventListView: View {
    @Bindable var viewModel: TraceEventListViewModel

    var body: some View {
        let events = viewModel.filteredEvents

        if events.isEmpty {
            EmptyStateView(
                symbolName: "list.bullet.rectangle.portrait",
                title: "No events in this trace",
                subtitle: "Events will appear when spans contain telemetry data"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        eventRow(event: event)
                            .background(index % 2 == 0 ? DashboardTheme.Colors.surfaceRaised : DashboardTheme.Colors.windowBackground)
                    }
                }
            }
        }
    }

    private func eventRow(event: ClassifiedEvent) -> some View {
        HStack(spacing: 8) {
            // Timestamp
            Text(formatRelativeTime(event.relativeTime))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(DashboardTheme.Colors.textTertiary)
                .frame(width: 60, alignment: .trailing)

            // Category badge
            Text(event.category.displayName.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(event.category.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(event.category.color.opacity(0.12))
                .clipShape(.capsule)

            // Event name
            Text(event.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DashboardTheme.Colors.textPrimary)
                .lineLimit(1)

            Spacer()

            // Span name
            Text(event.spanName)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(DashboardTheme.Colors.textQuaternary)
                .lineLimit(1)

            // Key attributes preview
            if let first = event.attributes.first {
                Text("\(first.0)=\(first.1)")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(DashboardTheme.Colors.textTertiary)
                    .lineLimit(1)
                    .frame(maxWidth: 200, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func formatRelativeTime(_ interval: TimeInterval) -> String {
        if interval < 1 {
            return String(format: "%.0fms", interval * 1000)
        }
        return String(format: "%.2fs", interval)
    }
}
