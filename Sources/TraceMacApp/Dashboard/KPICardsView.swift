import SwiftUI
import TerraTraceKit

struct KPICardsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let metrics = DashboardViewModel.compute(from: appState.traces)

    HStack(spacing: DashboardTheme.cardGap) {
        KPICardView(
            symbolName: "doc.text.magnifyingglass",
            label: "Total Traces",
            value: "\(metrics.totalTraces)"
        )

            KPICardView(
                symbolName: "clock",
                label: "Avg Duration",
                value: TraceFormatter.duration(metrics.averageDuration)
            )

            KPICardView(
                symbolName: "exclamationmark.triangle",
                label: "Error Rate",
                value: formattedErrorRate(metrics.errorRate),
                accent: metrics.errorRate > 0 ? DashboardTheme.accentError : DashboardTheme.accentNormal
            )

            KPICardView(
                symbolName: "point.3.connected.trianglepath.dotted",
                label: "Total Spans",
                value: "\(metrics.totalSpans)"
            )

            KPICardView(
                symbolName: "person.3",
                label: "Unique Agents",
                value: "\(metrics.uniqueAgents)"
            )

            KPICardView(
                symbolName: "chart.bar",
                label: "p50",
                value: TraceFormatter.duration(metrics.p50Duration)
            )

        KPICardView(
            symbolName: "chart.bar.fill",
            label: "p95",
            value: TraceFormatter.duration(metrics.p95Duration)
        )

        KPICardView(
            symbolName: "chart.bar.xaxis",
            label: "p99",
            value: TraceFormatter.duration(metrics.p99Duration),
            accent: metrics.p99Duration > 5.0 ? DashboardTheme.accentError : DashboardTheme.accentNormal
        )

        KPICardView(
            symbolName: "timer",
            label: "TTFT p50",
            value: TraceFormatter.duration(metrics.ttftP50)
        )

        KPICardView(
            symbolName: "gauge",
            label: "TTFT p95",
            value: TraceFormatter.duration(metrics.ttftP95)
        )

        KPICardView(
            symbolName: "arrow.triangle.branch",
            label: "Split (Prompt/Decode)",
            value: String(format: "%.0f%% / %.0f%%", metrics.promptDecodeSplit * 100, (1 - metrics.promptDecodeSplit) * 100)
        )

        KPICardView(
            symbolName: "waveform.path.ecg",
            label: "Stalled Tokens",
            value: "\(metrics.stalledTokenCount)"
        )

        KPICardView(
            symbolName: "bolt.horizontal",
            label: "Stall Rate",
            value: String(format: "%.1f%%", metrics.stalledTokenRate * 100),
            accent: metrics.stalledTokenRate > 0.05 ? DashboardTheme.accentWarning : DashboardTheme.accentNormal
        )

        KPICardView(
            symbolName: "lightbulb",
            label: "Recommendations",
            value: "\(metrics.recommendationCount)"
        )

        KPICardView(
            symbolName: "exclamationmark.triangle",
            label: "Anomalies",
            value: "\(metrics.anomalyCount)",
            accent: metrics.anomalyCount > 0 ? DashboardTheme.accentError : DashboardTheme.accentNormal
        )

        KPICardView(
            symbolName: "cpu",
            label: "Hardware Events",
            value: "\(metrics.hardwareTelemetryEventCount)"
        )

        KPICardView(
            symbolName: "desktopcomputer",
            label: "Runtime Parity",
            value: runtimeBadgeSummary(metrics.runtimeCounts)
        )
    }
    }

    private func formattedErrorRate(_ rate: Double) -> String {
        let percentage = rate * 100
        if percentage == 0 {
            return "0%"
        }
        return percentage.formatted(.number.precision(.fractionLength(1))) + "%"
    }

    private func runtimeBadgeSummary(_ counts: [TraceRuntimeFilter: Int]) -> String {
        let active = counts
            .filter { $0.key != .all && $0.value > 0 && $0.key != .other }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.title < rhs.key.title
                }
                return lhs.value > rhs.value
            }

        guard let top = active.first else {
            return "\(counts[.other, default: 0])"
        }
        return "\(top.key.title):\(top.value)"
    }
}
