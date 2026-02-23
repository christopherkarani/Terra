import SwiftUI
import TerraTraceKit

struct TraceRowView: View {
    let trace: Trace
    var isLive: Bool = false

    @Environment(RelativeClock.self) private var clock
    @State private var isHovered = false
    @State private var isFlashing = false
    @State private var isRunningPulse = false
    @State private var relativeTime: String = ""
    @State private var metrics: TraceRowMetrics?

    var body: some View {
        HStack(spacing: 8) {
            // Status dot
            statusDot

            // Name + runtime/model + metrics (3-line layout)
            VStack(alignment: .leading, spacing: 2) {
                // Line 1: display name + duration
                HStack {
                    Text(trace.displayName)
                        .font(DashboardTheme.Fonts.rowTitle)
                        .foregroundStyle(DashboardTheme.Colors.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text(TraceFormatter.duration(trace.duration))
                        .font(Font.system(size: 11, design: .monospaced))
                        .foregroundStyle(DashboardTheme.Colors.textSecondary)
                }

                // Line 2: runtime pill + model name (if available)
                if let metrics, metrics.runtime != .other {
                    HStack(spacing: 6) {
                        // Runtime indicator
                        HStack(spacing: 3) {
                            Circle()
                                .fill(metrics.runtime.accentColor)
                                .frame(width: 5, height: 5)
                            Text(metrics.runtime.title)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(DashboardTheme.Colors.textSecondary)
                        }

                        // Model name
                        if let modelName = metrics.modelName {
                            Text(modelName)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(DashboardTheme.Colors.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }

                // Line 3: TTFT + tok/s + span count + error badge + relative time
                HStack(spacing: 0) {
                    metaLine

                    if errorCount > 0 {
                        Text(" ")
                        Text("\(errorCount) err")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(DashboardTheme.Colors.accentError)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(DashboardTheme.Colors.errorBackground)
                            .clipShape(.rect(cornerRadius: DashboardTheme.Spacing.cornerRadiusSmall))
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: DashboardTheme.Spacing.cornerRadius)
                .fill(flashBackground)
        )
        .contentShape(.rect)
        .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.micro), value: isHovered)
        .onHover { hovering in isHovered = hovering }
        .onAppear {
            relativeTime = Self.formatRelativeTime(trace.fileTimestamp)
            metrics = TraceRowMetrics(trace: trace)
            // New-trace flash: if trace is <5 seconds old
            if trace.fileTimestamp.timeIntervalSinceNow > -5 {
                isFlashing = true
                withAnimation(.easeOut(duration: 1.5)) {
                    isFlashing = false
                }
            }
            // Running-span pulse
            if hasRunningSpan {
                isRunningPulse = true
            }
        }
        .onChange(of: clock.tick) {
            relativeTime = Self.formatRelativeTime(trace.fileTimestamp)
        }
    }

    // MARK: - Meta line

    private var metaSeparator: some View {
        Text(" \u{00b7} ")
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(DashboardTheme.Colors.textQuaternary)
    }

    @ViewBuilder
    private var metaLine: some View {
        // TTFT
        if let formattedTTFT = metrics?.formattedTTFT {
            let ttftWarning = (metrics?.ttftMs ?? 0) > 2000
            HStack(spacing: 2) {
                Text("TTFT")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(DashboardTheme.Colors.textQuaternary)
                Text(formattedTTFT)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(ttftWarning ? DashboardTheme.Colors.accentWarning : DashboardTheme.Colors.textTertiary)
            }
            metaSeparator
        }

        // Tok/s
        if let formattedTPS = metrics?.formattedTokensPerSec {
            Text(formattedTPS)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(DashboardTheme.Colors.textTertiary)
            metaSeparator
        }

        // Span count
        Text("\(trace.spans.count) spans")
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(DashboardTheme.Colors.textTertiary)

        metaSeparator

        // Relative time
        Text(relativeTime)
            .font(DashboardTheme.Fonts.rowMeta)
            .foregroundStyle(DashboardTheme.Colors.textTertiary)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var statusDot: some View {
        if hasRunningSpan {
            // Running span: blue dot with pulsing ring
            ZStack {
                Circle()
                    .fill(DashboardTheme.Colors.accentActive)
                    .frame(width: 6, height: 6)

                Circle()
                    .stroke(DashboardTheme.Colors.accentActive.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 10, height: 10)
                    .scaleEffect(isRunningPulse ? 1.5 : 1.0)
                    .opacity(isRunningPulse ? 0.0 : 0.6)
                    .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.pulse), value: isRunningPulse)
            }
            .frame(width: 12, height: 12)
        } else {
            Circle()
                .fill(trace.hasError ? DashboardTheme.Colors.accentError : DashboardTheme.Colors.accentSuccess)
                .frame(width: 6, height: 6)
        }
    }

    private var flashBackground: Color {
        if isFlashing {
            return DashboardTheme.Colors.accentActive.opacity(0.12)
        }
        return isHovered ? DashboardTheme.Colors.surfaceHover : .clear
    }

    // MARK: - Helpers

    private var errorCount: Int {
        trace.spans.filter { $0.status.isError }.count
    }

    private var hasRunningSpan: Bool {
        trace.spans.contains { $0.endTime <= $0.startTime }
    }

    private static func formatRelativeTime(_ date: Date) -> String {
        TraceFormatter.relativeTime(date)
    }
}
