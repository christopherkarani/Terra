import SwiftUI
import TerraTraceKit
import OpenTelemetrySdk

/// Individual row in the span event stream: timestamp, kind badge, span name, duration, token count.
/// Expands inline to show SpanInlineDetail when tapped.
struct SpanStreamRow: View {
    let span: SpanData
    let isExpanded: Bool
    let isSelected: Bool
    var onTap: () -> Void = {}

    @State private var isHovered = false

    private var kind: FlowNodeKind { FlowNodeKind.classify(span: span) }
    private var duration: TimeInterval { span.endTime.timeIntervalSince(span.startTime) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed row
            Button(action: onTap) {
                HStack(spacing: DashboardTheme.Spacing.md) {
                    // Expand/collapse chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(DashboardTheme.Colors.textQuaternary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.standard), value: isExpanded)
                        .frame(width: 8)

                    // Timestamp
                    Text(TraceFormatter.timestamp(span.startTime))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DashboardTheme.Colors.textQuaternary)
                        .frame(width: 64, alignment: .leading)

                    // Kind badge
                    kindBadge

                    // Span name
                    Text(kind.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DashboardTheme.Colors.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    // Token count (if inference)
                    if case .inference(_, _, let output, _) = kind, output > 0 {
                        Text("\(output)t")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(DashboardTheme.Colors.textTertiary)
                    }

                    // Duration
                    Text(TraceFormatter.duration(duration))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(durationColor)
                        .frame(width: 52, alignment: .trailing)

                    // Error indicator
                    if span.status.isError {
                        Circle()
                            .fill(DashboardTheme.Colors.accentError)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.horizontal, DashboardTheme.Spacing.lg)
                .padding(.vertical, 6)
                .background(isSelected ? DashboardTheme.Colors.surfaceActive : (isHovered ? DashboardTheme.Colors.surfaceHover : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .accessibilityLabel("\(kindShortLabel) span, \(kind.label), \(TraceFormatter.duration(duration))")
            .accessibilityHint(isExpanded ? "Collapse detail" : "Expand detail")

            // Expanded inline detail
            if isExpanded {
                SpanInlineDetail(span: span)
                    .padding(.horizontal, DashboardTheme.Spacing.lg)
                    .padding(.vertical, DashboardTheme.Spacing.md)
                    .background(DashboardTheme.Colors.surfaceRaised)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var kindBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: kind.icon)
                .font(.system(size: 8))
            Text(kindShortLabel)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(kindColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(kindColor.opacity(0.08))
        .clipShape(.capsule)
    }

    private var kindShortLabel: String {
        switch kind {
        case .agent:      return "AGENT"
        case .inference:  return "INF"
        case .tool:       return "TOOL"
        case .stage:      return "STAGE"
        case .embedding:  return "EMBED"
        case .safetyCheck: return "SAFETY"
        case .generic:    return "SPAN"
        }
    }

    private var kindColor: Color {
        switch kind {
        case .agent:      return DashboardTheme.Colors.nodeAgent
        case .inference:  return DashboardTheme.Colors.nodeInference
        case .tool:       return DashboardTheme.Colors.nodeTool
        case .stage:      return DashboardTheme.Colors.nodeStage
        case .embedding:  return DashboardTheme.Colors.nodeEmbedding
        case .safetyCheck: return DashboardTheme.Colors.nodeSafety
        case .generic:    return DashboardTheme.Colors.nodeStage
        }
    }

    private var durationColor: Color {
        if duration < 0.1 { return DashboardTheme.Colors.accentSuccess }
        if duration < 1.0 { return DashboardTheme.Colors.accentWarning }
        return DashboardTheme.Colors.accentError
    }
}
