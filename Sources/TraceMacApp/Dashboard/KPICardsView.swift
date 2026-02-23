import SwiftUI
import TerraTraceKit

/// Full KPI grid shown in popover from the strip's "..." button.
/// Groups 18 metrics into sections: Performance, Streaming, Volume, Health.
struct KPIGridPopoverView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let metrics = DashboardViewModel.compute(from: appState.traces)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                kpiSection("PERFORMANCE") {
                    kpiRow("Avg Duration", TraceFormatter.duration(metrics.averageDuration))
                    kpiRow("p50", TraceFormatter.duration(metrics.p50Duration))
                    kpiRow("p95", TraceFormatter.duration(metrics.p95Duration))
                    kpiRow("p99", TraceFormatter.duration(metrics.p99Duration),
                           accent: metrics.p99Duration > 5.0 ? DashboardTheme.Colors.accentError : nil)
                    kpiRow("TTFT p50", TraceFormatter.duration(metrics.ttftP50))
                    kpiRow("TTFT p95", TraceFormatter.duration(metrics.ttftP95))
                    kpiRow("TTFT p99", TraceFormatter.duration(metrics.ttftP99),
                           accent: metrics.ttftP99 > 2.0 ? DashboardTheme.Colors.accentWarning : nil)
                }

                kpiSection("STREAMING") {
                    kpiRow("Prompt/Decode Split",
                           String(format: "%.0f%% / %.0f%%", metrics.promptDecodeSplit * 100, (1 - metrics.promptDecodeSplit) * 100))
                    kpiRow("Stalled Tokens", "\(metrics.stalledTokenCount)")
                    kpiRow("Stall Rate",
                           String(format: "%.1f%%", metrics.stalledTokenRate * 100),
                           accent: metrics.stalledTokenRate > 0.05 ? DashboardTheme.Colors.accentWarning : nil)
                }

                kpiSection("PIPELINE LATENCY") {
                    kpiRow("E2E p50", TraceFormatter.duration(metrics.e2eP50))
                    kpiRow("E2E p99", TraceFormatter.duration(metrics.e2eP99),
                           accent: metrics.e2eP99 > 5.0 ? DashboardTheme.Colors.accentError : nil)
                    kpiRow("Prompt Eval p50", TraceFormatter.duration(metrics.promptEvalP50))
                    kpiRow("Prompt Eval p99", TraceFormatter.duration(metrics.promptEvalP99),
                           accent: metrics.promptEvalP99 > 3.0 ? DashboardTheme.Colors.accentWarning : nil)
                    kpiRow("Decode p50", TraceFormatter.duration(metrics.decodeP50))
                    kpiRow("Decode p99", TraceFormatter.duration(metrics.decodeP99),
                           accent: metrics.decodeP99 > 3.0 ? DashboardTheme.Colors.accentWarning : nil)
                }

                kpiSection("VOLUME") {
                    kpiRow("Total Traces", "\(metrics.totalTraces)")
                    kpiRow("Total Spans", "\(metrics.totalSpans)")
                    kpiRow("Unique Agents", "\(metrics.uniqueAgents)")
                    kpiRow("Error Rate", formattedErrorRate(metrics.errorRate),
                           accent: metrics.errorRate > 0 ? DashboardTheme.Colors.accentError : nil)
                }

                kpiSection("HEALTH") {
                    kpiRow("Recommendations", "\(metrics.recommendationCount)")
                    kpiRow("Anomalies", "\(metrics.anomalyCount)",
                           accent: metrics.anomalyCount > 0 ? DashboardTheme.Colors.accentError : nil)
                    kpiRow("Hardware Events", "\(metrics.hardwareTelemetryEventCount)")
                    kpiRow("Runtime Parity", runtimeBadgeSummary(metrics.runtimeCounts))
                }
            }
        }
    }

    private func kpiSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(DashboardTheme.Fonts.sectionHeader)
                .foregroundStyle(DashboardTheme.Colors.textTertiary)

            content()
        }
    }

    private func kpiRow(_ label: String, _ value: String, accent: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(DashboardTheme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(accent ?? DashboardTheme.Colors.textPrimary)
        }
        .padding(.vertical, 2)
    }

    private func formattedErrorRate(_ rate: Double) -> String {
        TraceFormatter.errorRate(rate)
    }

    private func runtimeBadgeSummary(_ counts: [TraceRuntimeFilter: Int]) -> String {
        let active = counts
            .filter { $0.key != .all && $0.value > 0 && $0.key != .other }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key.title < rhs.key.title }
                return lhs.value > rhs.value
            }
        guard let top = active.first else { return "\(counts[.other, default: 0])" }
        return "\(top.key.title):\(top.value)"
    }
}

// Keep old name as alias for compilation
typealias KPICardsView = KPIGridPopoverView
