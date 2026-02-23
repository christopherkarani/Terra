import SwiftUI
import TerraTraceKit
import OpenTelemetrySdk

/// A single row in the span tree representing one span.
/// 5px status dot | name (12pt) | thin duration bar (60px, 3px height) | duration text (11pt mono).
/// Indent depth * 16.
struct SpanTreeRowView: View {
    let node: SpanTreeNode
    let isSelected: Bool

    var body: some View {
        HStack(spacing: DashboardTheme.Spacing.md) {
            statusDot
            nameLabel
            durationBar
            Spacer()
            durationLabel
        }
        .padding(.leading, CGFloat(node.depth) * 16)
        .padding(.vertical, 2)
        .contentShape(.rect)
    }
}

// MARK: - Subviews

private extension SpanTreeRowView {
    var statusDot: some View {
        Circle()
            .fill(node.span.status.isError ? DashboardTheme.Colors.accentError : DashboardTheme.Colors.accentSuccess)
            .frame(width: 5, height: 5)
    }

    var nameLabel: some View {
        Text(node.span.name)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(DashboardTheme.Colors.textPrimary)
            .lineLimit(1)
    }

    var durationBar: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(DashboardTheme.Colors.serviceColor(for: node.span.name).opacity(0.25))
            .frame(width: 60, height: 3)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(DashboardTheme.Colors.serviceColor(for: node.span.name))
                    .frame(width: max(2, node.durationFraction * 60), height: 3)
            }
    }

    var durationLabel: some View {
        Text(TraceFormatter.duration(
            node.span.endTime.timeIntervalSince(node.span.startTime)
        ))
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(DashboardTheme.Colors.textSecondary)
    }
}
