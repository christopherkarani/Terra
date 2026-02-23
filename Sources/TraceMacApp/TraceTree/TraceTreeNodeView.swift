import SwiftUI
import OpenTelemetrySdk

/// Individual node card for the horizontal trace tree.
/// Collapsed: icon + name + status dot + duration + tokens + chevron.
/// Expanded: collapsed header + TraceTreeDetailSection (grows taller, not wider).
struct TraceTreeNodeView: View {
    @ObservedObject var node: FlowGraphNode
    let span: SpanData
    let isSelected: Bool
    let isExpanded: Bool
    var onTap: () -> Void = {}

    @State private var isHovered = false
    @State private var tapScale: CGFloat = 1.0
    @State private var isPulsing = false
    @State private var glowIntensity: CGFloat = 0
    @State private var statusDotScale: CGFloat = 1.0
    @State private var previousStatus: FlowNodeStatus?

    private var accentColor: Color {
        switch node.kind {
        case .agent:      return DashboardTheme.Colors.nodeAgent
        case .inference:  return DashboardTheme.Colors.nodeInference
        case .tool:       return DashboardTheme.Colors.nodeTool
        case .stage:      return DashboardTheme.Colors.nodeStage
        case .embedding:  return DashboardTheme.Colors.nodeEmbedding
        case .safetyCheck: return DashboardTheme.Colors.nodeSafety
        case .generic:    return DashboardTheme.Colors.nodeStage
        }
    }

    private var cornerRadius: CGFloat {
        switch node.kind {
        case .agent: return 14
        case .stage: return 6
        default: return 10
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed header
            collapsedHeader
                .padding(.horizontal, DashboardTheme.Spacing.lg)
                .padding(.vertical, DashboardTheme.Spacing.md)

            // Expanded detail section
            if isExpanded {
                TraceTreeDetailSection(node: node, span: span)
                    .padding(.horizontal, DashboardTheme.Spacing.lg)
                    .padding(.bottom, DashboardTheme.Spacing.md)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: node.size.width, height: node.size.height)
        .background(isHovered ? DashboardTheme.Colors.surfaceHover : DashboardTheme.Colors.windowBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    borderColor,
                    lineWidth: isSelected ? 2 : 1
                )
        )
        // Left accent stripe (3px) with completion glow
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accentColor)
                .frame(width: 3)
                .padding(.vertical, 4)
                .brightness(glowIntensity * 0.5)
                .shadow(color: accentColor.opacity(glowIntensity), radius: glowIntensity * 6)
        }
        // Agent crown stripe (3px top edge)
        .overlay(alignment: .top) {
            if node.kind.isAgent {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor)
                    .frame(height: 3)
                    .padding(.horizontal, 4)
            }
        }
        // Error state is handled by borderColor — no separate overlay needed
        .shadow(
            color: isHovered ? DashboardTheme.Shadows.md.color : DashboardTheme.Shadows.sm.color,
            radius: isHovered ? DashboardTheme.Shadows.md.radius : DashboardTheme.Shadows.sm.radius,
            y: isHovered ? DashboardTheme.Shadows.md.y : DashboardTheme.Shadows.sm.y
        )
        .scaleEffect(tapScale)
        .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.micro), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                tapScale = 1.02
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    tapScale = 1.0
                }
            }
            onTap()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(node.kind.label), \(formattedDuration), \(node.status)"))
        .accessibilityAddTraits(.isButton)
        .onChange(of: node.status) { oldValue, newValue in
            if oldValue == .running && newValue == .completed {
                triggerCompletionCascade()
            }
        }
        .onAppear {
            previousStatus = node.status
        }
    }

    // MARK: - Collapsed Header

    private var collapsedHeader: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.sm) {
            // Row 1: icon + name + status dot + duration pill + chevron
            HStack(spacing: DashboardTheme.Spacing.md) {
                Image(systemName: node.kind.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(accentColor)

                Text(truncatedLabel)
                    .font(.system(
                        size: node.kind.isAgent ? 13 : 11,
                        weight: node.kind.isAgent ? .semibold : .medium,
                        design: node.kind.isAgent ? .default : .monospaced
                    ))
                    .foregroundStyle(DashboardTheme.Colors.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                statusDot

                durationPill

                // Expand/collapse chevron
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DashboardTheme.Colors.textTertiary)
            }

            // Row 2: token summary (if tokens > 0)
            if node.inputTokens > 0 || node.outputTokens > 0 {
                HStack(spacing: 4) {
                    Text("\(node.inputTokens)\u{2192}\(node.outputTokens) tok")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(DashboardTheme.Colors.textTertiary)

                    if let tps = node.tokensPerSecond {
                        Text("\u{00b7}")
                            .foregroundStyle(DashboardTheme.Colors.textQuaternary)
                        Text(String(format: "%.0f tok/s", tps))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(DashboardTheme.Colors.textTertiary)
                    }
                }
                .padding(.leading, 20) // align under name (past icon)
            }
        }
    }

    // MARK: - Status Dot

    @ViewBuilder
    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .scaleEffect(statusDotScale)
            .overlay {
                if node.status == .running {
                    Circle()
                        .stroke(statusColor.opacity(0.3), lineWidth: 2)
                        .frame(width: 12, height: 12)
                        .scaleEffect(isPulsing ? 1.6 : 1.0)
                        .opacity(isPulsing ? 0 : 0.8)
                        .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.pulse), value: isPulsing)
                        .onAppear { isPulsing = true }
                }
            }
    }

    private var statusColor: Color {
        switch node.status {
        case .completed: return DashboardTheme.Colors.accentSuccess
        case .error:     return DashboardTheme.Colors.accentError
        case .running:   return DashboardTheme.Colors.accentActive
        case .pending:   return DashboardTheme.Colors.accentWarning
        }
    }

    // MARK: - Duration Pill

    private var durationPill: some View {
        Text(formattedDuration)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(durationColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(durationColor.opacity(0.08))
            .clipShape(Capsule())
    }

    private var formattedDuration: String {
        if node.duration < 1 {
            return String(format: "%.0fms", node.duration * 1000)
        } else {
            return String(format: "%.1fs", node.duration)
        }
    }

    private var durationColor: Color {
        if node.duration < 0.1 { return DashboardTheme.Colors.accentSuccess }
        if node.duration < 1.0 { return DashboardTheme.Colors.accentWarning }
        return DashboardTheme.Colors.accentError
    }

    // MARK: - Completion Cascade

    private func triggerCompletionCascade() {
        // Flash accent stripe at 1.5x brightness for 0.15s
        withAnimation(.easeIn(duration: 0.08)) {
            glowIntensity = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.2)) {
                glowIntensity = 0
            }
        }

        // Status dot scale pop: 1.0 → 1.2 → 1.0 over 0.2s
        withAnimation(.spring(response: 0.1, dampingFraction: 0.5)) {
            statusDotScale = 1.3
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.7)) {
                statusDotScale = 1.0
            }
        }

        // Stop pulsing now that span is completed
        isPulsing = false
    }

    // MARK: - Helpers

    private var truncatedLabel: String {
        let label = node.kind.label
        if isExpanded || label.count <= 20 { return label }
        return String(label.prefix(20)) + "\u{2026}"
    }

    private var borderColor: Color {
        if isSelected {
            return accentColor
        }
        if node.status == .error {
            return DashboardTheme.Colors.accentError
        }
        if isHovered {
            return DashboardTheme.Colors.borderStrong
        }
        return DashboardTheme.Colors.borderDefault
    }
}
