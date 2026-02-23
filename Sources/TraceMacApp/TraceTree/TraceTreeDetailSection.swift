import SwiftUI
import OpenTelemetrySdk

/// Expanded detail content rendered inside TraceTreeNodeView when a node is expanded.
/// Shows model, tokens, latency, tool info, hardware metrics, and events.
struct TraceTreeDetailSection: View {
    let node: FlowGraphNode
    let span: SpanData

    // Section label style: 9pt semibold uppercase, 0.8pt tracking
    private let sectionLabelFont = Font.system(size: 9, weight: .semibold)
    // Value style: 11pt semibold monospaced
    private let valueFont = Font.system(size: 11, weight: .semibold, design: .monospaced)
    private let chipFont = Font.system(size: 8, weight: .medium)

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.md) {
            Divider()
                .foregroundStyle(DashboardTheme.Colors.borderDefault)

            // Model section
            if let model = node.model, !model.isEmpty {
                sectionRow(label: "MODEL", value: model)
            }

            // Tokens section
            if node.inputTokens > 0 || node.outputTokens > 0 {
                tokensSection
            }

            // Latency section
            if node.ttftMs != nil || node.tokensPerSecond != nil || node.duration > 0 {
                latencySection
            }

            // Agent section
            if case .agent(_, let agentId) = node.kind {
                agentSection(agentId: agentId)
            }

            // Tool section
            if case .tool(let name, let callID, let type) = node.kind {
                toolSection(name: name, callID: callID, type: type)
            }

            // Prompt section
            promptSection

            // Completion / thinking section
            completionSection

            // Finish reason
            if let finishReason = stringAttribute("terra.content.finish_reason") {
                sectionRow(label: "FINISH", value: finishReason)
            }

            // Tool I/O section
            toolIOSection

            // Agent delegation section
            agentDelegationSection

            // System prompt section
            systemPromptSection

            // Hardware section
            hardwareSection

            // Events section
            eventsSection
        }
        .padding(.top, DashboardTheme.Spacing.sm)
    }

    // MARK: - Section Row

    private func sectionRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DashboardTheme.Spacing.md) {
            Text(label)
                .font(sectionLabelFont)
                .tracking(0.8)
                .foregroundStyle(DashboardTheme.Colors.textTertiary)
                .frame(width: 56, alignment: .leading)

            Text(value)
                .font(valueFont)
                .foregroundStyle(DashboardTheme.Colors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Tokens

    private var tokensSection: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DashboardTheme.Spacing.md) {
                Text("TOKENS")
                    .font(sectionLabelFont)
                    .tracking(0.8)
                    .foregroundStyle(DashboardTheme.Colors.textTertiary)
                    .frame(width: 56, alignment: .leading)

                Text("\(node.inputTokens)")
                    .font(valueFont)
                    .foregroundStyle(DashboardTheme.Colors.textPrimary)

                Image(systemName: "arrow.right")
                    .font(.system(size: 8))
                    .foregroundStyle(DashboardTheme.Colors.textQuaternary)

                Text("\(node.outputTokens)")
                    .font(valueFont)
                    .foregroundStyle(DashboardTheme.Colors.textPrimary)

                Spacer(minLength: 0)
            }

            // Proportional token bar
            tokenBar
        }
    }

    private var tokenBar: some View {
        let total = max(node.inputTokens + node.outputTokens, 1)
        let inputFraction = CGFloat(node.inputTokens) / CGFloat(total)

        return GeometryReader { geo in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(DashboardTheme.Colors.nodeInference)
                    .frame(width: geo.size.width * inputFraction)

                RoundedRectangle(cornerRadius: 2)
                    .fill(DashboardTheme.Colors.nodeEmbedding)
                    .frame(width: geo.size.width * (1 - inputFraction))
            }
        }
        .frame(height: 4)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .padding(.leading, 56 + DashboardTheme.Spacing.md)
    }

    // MARK: - Latency

    private var latencySection: some View {
        HStack(alignment: .firstTextBaseline, spacing: DashboardTheme.Spacing.md) {
            Text("LATENCY")
                .font(sectionLabelFont)
                .tracking(0.8)
                .foregroundStyle(DashboardTheme.Colors.textTertiary)
                .frame(width: 56, alignment: .leading)

            HStack(spacing: DashboardTheme.Spacing.sm) {
                if let ttft = node.ttftMs {
                    chip(text: String(format: "TTFT %.0fms", ttft))
                }

                chip(text: "E2E " + formattedDuration(node.duration))

                if let tps = node.tokensPerSecond {
                    chip(text: String(format: "%.1f tok/s", tps))
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Agent

    private func agentSection(agentId: String?) -> some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.sm) {
            if let agentId {
                HStack(spacing: DashboardTheme.Spacing.md) {
                    Text("AGENT ID")
                        .font(sectionLabelFont)
                        .tracking(0.8)
                        .foregroundStyle(DashboardTheme.Colors.textTertiary)
                        .frame(width: 56, alignment: .leading)

                    Text(String(agentId.prefix(20)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DashboardTheme.Colors.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
            }

            // Child count
            let childCountStr = span.attributes["terra.agent.child_count"]?.description
            let childCount = childCountStr.flatMap { Int($0) } ?? 0
            if childCount > 0 {
                sectionRow(label: "CHILDREN", value: "\(childCount) sub-span\(childCount == 1 ? "" : "s")")
            }

            // Aggregate tokens (if tracked)
            let totalTokensStr = span.attributes["terra.agent.total_tokens"]?.description
            if let totalTokensStr, let totalTokens = Int(totalTokensStr), totalTokens > 0 {
                sectionRow(label: "TOTAL TOK", value: formatNumber(totalTokens))
            }
        }
    }

    // MARK: - Tool

    private func toolSection(name: String, callID: String?, type: String?) -> some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.sm) {
            sectionRow(label: "TOOL", value: name)

            if let type {
                HStack(spacing: DashboardTheme.Spacing.md) {
                    Text("TYPE")
                        .font(sectionLabelFont)
                        .tracking(0.8)
                        .foregroundStyle(DashboardTheme.Colors.textTertiary)
                        .frame(width: 56, alignment: .leading)

                    chip(text: type)

                    Spacer(minLength: 0)
                }
            }

            if let callID {
                HStack(spacing: DashboardTheme.Spacing.md) {
                    Text("CALL ID")
                        .font(sectionLabelFont)
                        .tracking(0.8)
                        .foregroundStyle(DashboardTheme.Colors.textTertiary)
                        .frame(width: 56, alignment: .leading)

                    Text(String(callID.prefix(20)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DashboardTheme.Colors.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Hardware

    @ViewBuilder
    private var hardwareSection: some View {
        let gpuStr = span.attributes["terra.hw.gpu_utilization"]?.description
        let aneStr = span.attributes["terra.hw.ane_utilization"]?.description
        let thermal = span.attributes["terra.hw.thermal_state"]?.description
        let memStr = span.attributes["terra.hw.memory_delta_mb"]?.description

        let hasHardware = gpuStr != nil || aneStr != nil || thermal != nil || memStr != nil

        if hasHardware {
            HStack(alignment: .firstTextBaseline, spacing: DashboardTheme.Spacing.md) {
                Text("HARDWARE")
                    .font(sectionLabelFont)
                    .tracking(0.8)
                    .foregroundStyle(DashboardTheme.Colors.textTertiary)
                    .frame(width: 56, alignment: .leading)

                HStack(spacing: DashboardTheme.Spacing.sm) {
                    if let gpuStr, let gpu = Double(gpuStr) {
                        chip(text: String(format: "GPU %.0f%%", gpu * 100))
                    }
                    if let aneStr, let ane = Double(aneStr) {
                        chip(text: String(format: "ANE %.0f%%", ane * 100))
                    }
                    if let thermal {
                        chip(text: thermal.capitalized)
                    }
                    if let memStr {
                        chip(text: "+\(memStr) MB")
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Events

    @ViewBuilder
    private var eventsSection: some View {
        let events = span.events
        let anomalies = events.filter { $0.name.contains("anomaly") }.count
        let recommendations = events.filter { $0.name.contains("recommendation") }.count
        let stalls = events.filter { $0.name.contains("stall") }.count

        if anomalies > 0 || recommendations > 0 || stalls > 0 {
            HStack(alignment: .firstTextBaseline, spacing: DashboardTheme.Spacing.md) {
                Text("EVENTS")
                    .font(sectionLabelFont)
                    .tracking(0.8)
                    .foregroundStyle(DashboardTheme.Colors.textTertiary)
                    .frame(width: 56, alignment: .leading)

                HStack(spacing: DashboardTheme.Spacing.sm) {
                    if anomalies > 0 {
                        chip(text: "\(anomalies) anomal\(anomalies == 1 ? "y" : "ies")", tint: DashboardTheme.Colors.accentError)
                    }
                    if recommendations > 0 {
                        chip(text: "\(recommendations) rec", tint: DashboardTheme.Colors.accentWarning)
                    }
                    if stalls > 0 {
                        chip(text: "\(stalls) stall\(stalls == 1 ? "" : "s")", tint: DashboardTheme.Colors.accentError)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Prompt

    @ViewBuilder
    private var promptSection: some View {
        let promptText = stringAttribute("terra.content.prompt")
        let promptLengthStr = stringAttribute("terra.prompt.length")
        let promptLength = promptLengthStr.flatMap { Int($0) }

        if let promptText {
            contentBlock(label: "PROMPT", text: promptText, charCount: promptLength)
        } else if let promptLength, promptLength > 0 {
            sectionRow(label: "PROMPT", value: "\(formatNumber(promptLength)) chars")
        }
    }

    // MARK: - Completion / Thinking

    @ViewBuilder
    private var completionSection: some View {
        let completionText = stringAttribute("terra.content.completion")
        let completionLengthStr = stringAttribute("terra.completion.length")
        let completionLength = completionLengthStr.flatMap { Int($0) }

        if let completionText {
            contentBlock(label: "OUTPUT", text: completionText, charCount: completionLength)
        } else if let completionLength, completionLength > 0 {
            sectionRow(label: "OUTPUT", value: "\(formatNumber(completionLength)) chars")
        }

        let thinkingText = stringAttribute("terra.content.thinking")
        let thinkingLengthStr = stringAttribute("terra.thinking.length")
        let thinkingLength = thinkingLengthStr.flatMap { Int($0) }

        if let thinkingText {
            contentBlock(label: "THINKING", text: thinkingText, charCount: thinkingLength, tint: DashboardTheme.Colors.accentWarning)
        } else if let thinkingLength, thinkingLength > 0 {
            HStack(alignment: .firstTextBaseline, spacing: DashboardTheme.Spacing.md) {
                Text("THINKING")
                    .font(sectionLabelFont)
                    .tracking(0.8)
                    .foregroundStyle(DashboardTheme.Colors.textTertiary)
                    .frame(width: 56, alignment: .leading)

                chip(text: "\(formatNumber(thinkingLength)) chars", tint: DashboardTheme.Colors.accentWarning)

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Tool I/O

    @ViewBuilder
    private var toolIOSection: some View {
        let toolInput = stringAttribute("terra.content.tool_input")
        let toolInputLengthStr = stringAttribute("terra.tool_input.length")
        let toolInputLength = toolInputLengthStr.flatMap { Int($0) }

        if let toolInput {
            contentBlock(label: "INPUT", text: toolInput, charCount: toolInputLength, tint: DashboardTheme.Colors.nodeTool)
        } else if let toolInputLength, toolInputLength > 0 {
            sectionRow(label: "INPUT", value: "\(formatNumber(toolInputLength)) chars")
        }

        let toolOutput = stringAttribute("terra.content.tool_output")
        let toolOutputLengthStr = stringAttribute("terra.tool_output.length")
        let toolOutputLength = toolOutputLengthStr.flatMap { Int($0) }

        if let toolOutput {
            contentBlock(label: "RESULT", text: toolOutput, charCount: toolOutputLength, tint: DashboardTheme.Colors.accentSuccess)
        } else if let toolOutputLength, toolOutputLength > 0 {
            sectionRow(label: "RESULT", value: "\(formatNumber(toolOutputLength)) chars")
        }
    }

    // MARK: - Agent Delegation

    @ViewBuilder
    private var agentDelegationSection: some View {
        let delegation = stringAttribute("terra.content.agent_delegation_prompt")
        let delegationLengthStr = stringAttribute("terra.agent_delegation.length")
        let delegationLength = delegationLengthStr.flatMap { Int($0) }

        if let delegation {
            contentBlock(label: "DELEG", text: delegation, charCount: delegationLength, tint: DashboardTheme.Colors.nodeAgent)
        } else if let delegationLength, delegationLength > 0 {
            sectionRow(label: "DELEG", value: "\(formatNumber(delegationLength)) chars")
        }
    }

    // MARK: - System Prompt

    @ViewBuilder
    private var systemPromptSection: some View {
        let sysPrompt = stringAttribute("terra.content.system_prompt")
        let sysLengthStr = stringAttribute("terra.system_prompt.length")
        let sysLength = sysLengthStr.flatMap { Int($0) }

        if let sysPrompt {
            contentBlock(label: "SYSTEM", text: sysPrompt, charCount: sysLength)
        } else if let sysLength, sysLength > 0 {
            sectionRow(label: "SYSTEM", value: "\(formatNumber(sysLength)) chars")
        }
    }

    // MARK: - Content Block

    private func contentBlock(
        label: String,
        text: String,
        charCount: Int?,
        maxLines: Int = 4,
        tint: Color = DashboardTheme.Colors.textTertiary
    ) -> some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DashboardTheme.Spacing.md) {
                Text(label)
                    .font(sectionLabelFont)
                    .tracking(0.8)
                    .foregroundStyle(DashboardTheme.Colors.textTertiary)
                    .frame(width: 56, alignment: .leading)

                if let charCount {
                    chip(text: "\(formatNumber(charCount)) chars", tint: tint)
                }

                Spacer(minLength: 0)
            }

            // Content preview
            Text(text)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DashboardTheme.Colors.textSecondary)
                .lineLimit(maxLines)
                .padding(.horizontal, DashboardTheme.Spacing.md)
                .padding(.vertical, DashboardTheme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DashboardTheme.Colors.surfaceHover.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.leading, 56 + DashboardTheme.Spacing.md)
        }
    }

    // MARK: - Helpers

    private func stringAttribute(_ key: String) -> String? {
        guard let value = span.attributes[key]?.description else { return nil }
        return value.isEmpty ? nil : value
    }

    private func chip(text: String, tint: Color = DashboardTheme.Colors.textTertiary) -> some View {
        Text(text)
            .font(chipFont)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.08))
            .clipShape(Capsule())
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else {
            return String(format: "%.1fs", duration)
        }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1000 {
            return String(format: "%.1fK", Double(n) / 1000)
        }
        return "\(n)"
    }
}
