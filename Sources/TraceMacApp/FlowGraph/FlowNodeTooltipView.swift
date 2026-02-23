import SwiftUI

/// Hover tooltip showing span details.
/// White background, 1px borderStrong, 8px radius, 4px shadow.
/// 220px wide. Appears after 400ms hover delay.
struct FlowNodeTooltipView: View {
    let node: FlowGraphNode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(node.spanName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DashboardTheme.Colors.textPrimary)

            Divider()

            tooltipRow("Duration", value: formattedDuration)
            tooltipRow("Span ID", value: String(node.spanId.prefix(12)))

            if let model = node.model {
                tooltipRow("Model", value: model)
            }

            if node.inputTokens > 0 {
                tooltipRow("Input Tokens", value: "\(node.inputTokens)")
            }

            if node.outputTokens > 0 {
                tooltipRow("Output Tokens", value: "\(node.outputTokens)")
            }

            if let ttft = node.ttftMs {
                tooltipRow("TTFT", value: String(format: "%.0fms", ttft))
            }

            if let tps = node.tokensPerSecond {
                tooltipRow("Throughput", value: String(format: "%.1f tok/s", tps))
            }
        }
        .padding(DashboardTheme.Spacing.lg)
        .frame(width: 220)
        .background(DashboardTheme.Colors.windowBackground)
        .clipShape(.rect(cornerRadius: DashboardTheme.Spacing.cornerRadiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTheme.Spacing.cornerRadiusLarge)
                .strokeBorder(DashboardTheme.Colors.borderStrong, lineWidth: 1)
        )
        .shadow(color: DashboardTheme.Shadows.lg.color, radius: DashboardTheme.Shadows.lg.radius, y: DashboardTheme.Shadows.lg.y)
    }

    private func tooltipRow(_ key: String, value: String) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DashboardTheme.Colors.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DashboardTheme.Colors.textSecondary)
        }
    }

    private var formattedDuration: String {
        if node.duration < 1 {
            return String(format: "%.0fms", node.duration * 1000)
        }
        return String(format: "%.2fs", node.duration)
    }
}
