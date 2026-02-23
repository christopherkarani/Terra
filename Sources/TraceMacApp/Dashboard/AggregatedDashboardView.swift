import SwiftUI
import TerraTraceKit

/// Aggregated KPI dashboard shown in the content column when no trace is selected.
/// Replaces the "Select a trace" empty state with immediately visible performance data.
struct AggregatedDashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var appeared = false

    var body: some View {
        if appState.traces.isEmpty {
            EmptyStateView(
                symbolName: "waveform.path.ecg",
                title: "No traces yet",
                subtitle: "Start an inference with a connected runtime to see performance data",
                buttonTitle: "Quick Setup",
                action: { appState.setupOpenClawTracing() }
            )
        } else {
            dashboardContent
        }
    }

    private var dashboardContent: some View {
        let metrics = DashboardViewModel.compute(from: appState.traces)

        return ScrollView {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.xxl) {
                // OVERVIEW section
                overviewSection(metrics: metrics)

                // RUNTIMES section
                runtimesSection(metrics: metrics)

                // HEALTH section
                healthSection(metrics: metrics)
            }
            .padding(DashboardTheme.Spacing.xxl)
        }
        .background(DashboardTheme.Colors.windowBackground)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.entrance), value: appeared)
        .onAppear { appeared = true }
    }

    // MARK: - Overview

    private func overviewSection(metrics: DashboardMetrics) -> some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
            HStack {
                sectionHeader("OVERVIEW")
                Spacer()
                if let lastReceived = appState.lastTraceReceivedAt {
                    Text("Last trace: \(relativeTime(lastReceived))")
                        .font(DashboardTheme.Fonts.rowMeta)
                        .foregroundStyle(DashboardTheme.Colors.textQuaternary)
                }
            }

            Grid(alignment: .topLeading, horizontalSpacing: DashboardTheme.Spacing.lg, verticalSpacing: DashboardTheme.Spacing.lg) {
                GridRow {
                    MetricCard(label: "TRACES", value: "\(metrics.totalTraces)")
                    MetricCard(
                        label: "ERROR RATE",
                        value: formattedErrorRate(metrics.errorRate),
                        accent: metrics.errorRate > 0 ? DashboardTheme.Colors.accentError : nil
                    )
                    MetricCard(label: "EVENTS", value: "\(metrics.totalEventCount)")
                }
                GridRow {
                    MetricCard(
                        label: "PEAK GPU",
                        value: metrics.peakGPUPercent > 0 ? String(format: "%.1f%%", metrics.peakGPUPercent) : "\u{2014}"
                    )
                    MetricCard(
                        label: "PEAK MEM",
                        value: metrics.peakMemoryMB > 0 ? String(format: "%.0f MB", metrics.peakMemoryMB) : "\u{2014}"
                    )
                    MetricCard(
                        label: "TTFT",
                        value: TraceFormatter.duration(metrics.ttftP50),
                        subtitle: "p50"
                    )
                }
                GridRow {
                    MetricCard(
                        label: "DURATION",
                        value: TraceFormatter.duration(metrics.p95Duration),
                        subtitle: "p95",
                        accent: metrics.p95Duration > 3.0 ? DashboardTheme.Colors.accentWarning : nil
                    )
                    MetricCard(
                        label: "STALL RATE",
                        value: formattedStallRate(metrics.stalledTokenRate),
                        accent: metrics.stalledTokenRate > 0.05 ? DashboardTheme.Colors.accentWarning : nil
                    )
                    MetricCard(
                        label: "DECODE",
                        value: TraceFormatter.duration(metrics.decodeP50),
                        subtitle: "p50"
                    )
                }
            }
        }
    }

    // MARK: - Runtimes

    private func runtimesSection(metrics: DashboardMetrics) -> some View {
        let activeRuntimes = metrics.runtimeCounts
            .filter { $0.key != .all && $0.key != .other && $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key.title < rhs.key.title }
                return lhs.value > rhs.value
            }

        return Group {
            if !activeRuntimes.isEmpty {
                VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
                    sectionHeader("RUNTIMES")

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(activeRuntimes, id: \.key) { entry in
                                runtimeIndicator(runtime: entry.key, count: entry.value)
                            }
                        }
                    }
                }
            }
        }
    }

    private func runtimeIndicator(runtime: TraceRuntimeFilter, count: Int) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(runtime.accentColor)
                .frame(width: 6, height: 6)

            Text(runtime.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DashboardTheme.Colors.textSecondary)

            Text("\(count)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(DashboardTheme.Colors.textTertiary)
                .contentTransition(.numericText())
                .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.standard), value: count)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DashboardTheme.Colors.surfaceRaised)
        .clipShape(.rect(cornerRadius: DashboardTheme.Spacing.cornerRadius))
    }

    // MARK: - Health

    private func healthSection(metrics: DashboardMetrics) -> some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
            sectionHeader("HEALTH")

            Grid(alignment: .topLeading, horizontalSpacing: DashboardTheme.Spacing.lg, verticalSpacing: 0) {
                GridRow {
                    healthCard(metrics: metrics)
                }
            }
        }
    }

    private func healthCard(metrics: DashboardMetrics) -> some View {
        VStack(spacing: 0) {
            healthRow("Anomalies", "\(metrics.anomalyCount)",
                      accent: metrics.anomalyCount > 0 ? DashboardTheme.Colors.accentError : nil)
            healthRow("Recommendations", "\(metrics.recommendationCount)")
            healthRow("Hardware Events", "\(metrics.hardwareTelemetryEventCount)")
            healthRow("Unique Agents", "\(metrics.uniqueAgents)")
        }
        .padding(DashboardTheme.Spacing.cardPadding)
        .dashboardCard()
    }

    private func healthRow(_ label: String, _ value: String, accent: Color? = nil) -> some View {
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

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(DashboardTheme.Fonts.sectionHeader)
            .foregroundStyle(DashboardTheme.Colors.textTertiary)
    }

    private func formattedErrorRate(_ rate: Double) -> String {
        TraceFormatter.errorRate(rate)
    }

    private func formattedStallRate(_ rate: Double) -> String {
        let percentage = rate * 100
        if percentage == 0 { return "0%" }
        return percentage.formatted(.number.precision(.fractionLength(1))) + "%"
    }

    private func relativeTime(_ date: Date) -> String {
        TraceFormatter.relativeTime(date)
    }
}

// MARK: - MetricCard

private struct MetricCard: View {
    let label: String
    let value: String
    var subtitle: String? = nil
    var accent: Color? = nil

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(DashboardTheme.Fonts.sectionHeader)
                .foregroundStyle(DashboardTheme.Colors.textTertiary)

            Text(value)
                .font(DashboardTheme.Fonts.kpiValue)
                .foregroundStyle(accent ?? DashboardTheme.Colors.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.standard), value: value)

            if let subtitle {
                Text(subtitle)
                    .font(DashboardTheme.Fonts.rowMeta)
                    .foregroundStyle(DashboardTheme.Colors.textQuaternary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DashboardTheme.Spacing.cardPadding)
        .background(DashboardTheme.Colors.windowBackground)
        .clipShape(.rect(cornerRadius: DashboardTheme.Spacing.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTheme.Spacing.cornerRadius)
                .strokeBorder(
                    isHovered ? DashboardTheme.Colors.borderStrong : DashboardTheme.Colors.borderDefault,
                    lineWidth: 1
                )
        )
        .onHover { hovering in isHovered = hovering }
        .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.micro), value: isHovered)
    }
}
