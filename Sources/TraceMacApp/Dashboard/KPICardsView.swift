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
        }
    }

    private func formattedErrorRate(_ rate: Double) -> String {
        let percentage = rate * 100
        if percentage == 0 {
            return "0%"
        }
        return percentage.formatted(.number.precision(.fractionLength(1))) + "%"
    }
}
