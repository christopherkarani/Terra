import SwiftUI

/// Individual node card — the visual identity of Terra.
/// Each node type has a distinct icon, accent color, and shape language.
/// Content reveals progressively based on `RevealPhase`.
struct FlowNodeView: View {
    @ObservedObject var node: FlowGraphNode
    let isSelected: Bool
    let isExpanded: Bool
    var onTap: () -> Void = {}

    @State private var isHovered = false
    @State private var tapScale: CGFloat = 1.0
    @State private var isPulsing = false

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
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.sm) {
            // Always: icon + name + status dot
            headerRow

            // Phase 2+: duration pill + TTFT
            if node.revealPhase >= .metrics {
                durationPill
                if let ttft = node.ttftMs {
                    ttftLabel(ttft)
                }
            }

            // Phase 3+: live token count + TPS
            if node.revealPhase >= .streaming {
                tokenStreamRow
            }

            // Phase 4 (complete) OR user-expanded: all metadata + prompt preview
            if node.revealPhase >= .complete || isExpanded {
                expandedContent
                if let prompt = node.promptPreview {
                    promptPreviewLabel(prompt)
                }
            }
        }
        .padding(.horizontal, DashboardTheme.Spacing.lg)
        .padding(.vertical, DashboardTheme.Spacing.md)
        .frame(width: node.size.width, height: node.size.height)
        .background(DashboardTheme.Colors.windowBackground)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    isSelected ? accentColor : (isHovered ? DashboardTheme.Colors.borderStrong : DashboardTheme.Colors.borderDefault),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .overlay(alignment: .leading) {
            if case .agent = node.kind {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
        }
        .shadow(color: isHovered ? DashboardTheme.Shadows.sm.color : .clear, radius: DashboardTheme.Shadows.sm.radius, y: DashboardTheme.Shadows.sm.y)
        .scaleEffect(tapScale)
        .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.entrance), value: node.revealPhase)
        .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.micro), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(node.kind.label), \(formattedDuration), \(node.status)"))
        .accessibilityAddTraits(.isButton)
        .onTapGesture {
            DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.smooth) {
                tapScale = 1.02
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.smooth) {
                    tapScale = 1.0
                }
            }
            onTap()
        }
    }

    // MARK: - Header Row (always visible)

    private var headerRow: some View {
        HStack(spacing: DashboardTheme.Spacing.md) {
            Image(systemName: node.kind.icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(accentColor)

            Text(truncatedLabel)
                .font(.system(
                    size: node.kind.isAgent ? 13 : 10,
                    weight: node.kind.isAgent ? .semibold : .medium,
                    design: node.kind.isAgent ? .default : .monospaced
                ))
                .foregroundStyle(DashboardTheme.Colors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            statusDot
        }
    }

    private var truncatedLabel: String {
        let label = node.kind.label
        if isExpanded || label.count <= 18 { return label }
        return String(label.prefix(18)) + "\u{2026}"
    }

    // MARK: - Status Dot

    @ViewBuilder
    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
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
            .accessibilityLabel(Text(verbatim: "Status: \(node.status)"))
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
            .clipShape(.capsule)
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

    // MARK: - TTFT Label

    private func ttftLabel(_ ttft: Double) -> some View {
        Text(String(format: "TTFT %.0fms", ttft))
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(DashboardTheme.Colors.textTertiary)
    }

    // MARK: - Token Stream Row (phase 3+)

    private var tokenStreamRow: some View {
        HStack(spacing: 4) {
            let tokens = node.liveOutputTokens > 0 ? node.liveOutputTokens : node.outputTokens
            Text("\(tokens) tok")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(DashboardTheme.Colors.textTertiary)
                .contentTransition(.numericText())
                .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.standard), value: tokens)

            if let tps = node.liveTPS ?? node.tokensPerSecond {
                Text("\u{00b7}")
                    .foregroundStyle(DashboardTheme.Colors.textQuaternary)
                Text(String(format: "%.1f tok/s", tps))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(DashboardTheme.Colors.textTertiary)
                    .contentTransition(.numericText())
            }
        }
    }

    // MARK: - Expanded Content (phase 4 or zoomed)

    @ViewBuilder
    private var expandedContent: some View {
        switch node.kind {
        case .inference(_, let input, let output, _):
            HStack(spacing: 4) {
                Text("\(input)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(DashboardTheme.Colors.textTertiary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 7))
                    .foregroundStyle(DashboardTheme.Colors.textQuaternary)
                Text("\(output) tok")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(DashboardTheme.Colors.textTertiary)
            }

        case .tool(_, let callID, _):
            if let callID {
                Text(String(callID.prefix(12)))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(DashboardTheme.Colors.textQuaternary)
            }

        case .agent(_, let id):
            if let id {
                Text(String(id.prefix(12)))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(DashboardTheme.Colors.textQuaternary)
            }

        case .stage:
            if let count = node.stageTokenCount {
                Text("\(count) tok")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(DashboardTheme.Colors.textTertiary)
            }

        default:
            EmptyView()
        }
    }

    // MARK: - Prompt Preview

    private func promptPreviewLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(DashboardTheme.Colors.textQuaternary)
            .lineLimit(2)
            .padding(.top, 2)
    }
}
