import SwiftUI
import TerraTraceKit
import OpenTelemetrySdk

/// A single row in the span tree representing one span.
struct SpanTreeRowView: View {
    let node: SpanTreeNode
    let isSelected: Bool

    var body: some View {
        HStack(spacing: DashboardTheme.sectionSpacing) {
            statusDot
            nameLabel
            durationBar
            Spacer()
            if node.span.status.isError {
                StatusBadge(isError: true)
            }
            durationLabel
        }
        .padding(.leading, CGFloat(node.depth) * 16)
        .padding(.vertical, 2)
        .contentShape(.rect)
    }
}

// MARK: - Subviews

private struct StatusDotView: View {
    let isError: Bool

    var body: some View {
        Circle()
            .fill(isError ? DashboardTheme.accentError : DashboardTheme.accentNormal)
            .frame(width: 8, height: 8)
    }
}

private extension SpanTreeRowView {
    var statusDot: some View {
        StatusDotView(isError: node.span.status.isError)
    }

    var nameLabel: some View {
        Text(node.span.name)
            .font(DashboardTheme.rowTitle)
            .lineLimit(1)
    }

    var durationBar: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(DashboardTheme.Colors.serviceColor(for: node.span.name).opacity(0.3))
            .frame(width: 80, height: 6)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(DashboardTheme.Colors.serviceColor(for: node.span.name))
                    .frame(width: max(2, node.durationFraction * 80), height: 6)
            }
    }

    var durationLabel: some View {
        Text(TraceFormatter.duration(
            node.span.endTime.timeIntervalSince(node.span.startTime)
        ))
        .font(DashboardTheme.rowMeta)
        .foregroundStyle(.secondary)
    }
}
