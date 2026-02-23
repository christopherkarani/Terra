import SwiftUI
import TerraTraceKit

/// Compact horizontal KPI strip — 6 key metrics separated by dividers.
struct KPIStripView: View {
    @Environment(AppState.self) private var appState
    @State private var showMorePopover = false
    @State private var eventsFlash = false
    @State private var errorFlash = false
    @State private var previousEventCount: Int = 0
    @State private var previousErrorRate: Double = 0

    var body: some View {
        let metrics = DashboardViewModel.compute(from: appState.traces)

        HStack(spacing: 0) {
            kpiItem(label: "EVENTS", value: "\(metrics.totalEventCount)")
                .background(
                    RoundedRectangle(cornerRadius: DashboardTheme.Spacing.cornerRadiusSmall)
                        .fill(eventsFlash ? DashboardTheme.Colors.accentActive.opacity(0.08) : .clear)
                )

            stripDivider

            kpiItem(
                label: "PEAK GPU",
                value: metrics.peakGPUPercent > 0 ? String(format: "%.1f%%", metrics.peakGPUPercent) : "\u{2014}"
            )

            stripDivider

            kpiItem(
                label: "PEAK MEM",
                value: metrics.peakMemoryMB > 0 ? String(format: "%.0f MB", metrics.peakMemoryMB) : "\u{2014}"
            )

            stripDivider

            kpiItem(
                label: "ERRORS",
                value: formattedErrorRate(metrics.errorRate),
                accent: metrics.errorRate > 0 ? DashboardTheme.Colors.accentError : nil
            )
            .background(
                RoundedRectangle(cornerRadius: DashboardTheme.Spacing.cornerRadiusSmall)
                    .fill(errorFlash ? DashboardTheme.Colors.accentError.opacity(0.08) : .clear)
            )
            .accessibilityLabel("Error rate \(formattedErrorRate(metrics.errorRate)), tap to filter errors")
            .onTapGesture {
                guard metrics.errorRate > 0 else { return }
                appState.showOnlyErrors.toggle()
            }
            .onHover { hovering in
                if metrics.errorRate > 0 {
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if appState.showOnlyErrors {
                    Circle()
                        .fill(DashboardTheme.Colors.accentActive)
                        .frame(width: 5, height: 5)
                        .offset(x: -4, y: 4)
                }
            }

            stripDivider

            kpiItem(label: "DURATION", value: TraceFormatter.duration(metrics.p50Duration))

            stripDivider

            kpiItem(label: "SPANS", value: "\(metrics.totalSpans)")

            stripDivider

            Button {
                showMorePopover = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12))
                    .foregroundStyle(DashboardTheme.Colors.textTertiary)
                    .frame(width: 40)
                    .accessibilityLabel("Show all metrics")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showMorePopover) {
                KPIGridPopoverView()
                    .frame(width: 580, height: 520)
                    .padding()
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(DashboardTheme.Colors.windowBackground)
        .clipShape(.rect(cornerRadius: DashboardTheme.Spacing.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTheme.Spacing.cornerRadius)
                .strokeBorder(DashboardTheme.Colors.borderDefault, lineWidth: 1)
        )
        .onChange(of: metrics.totalEventCount) { oldValue, newValue in
            if newValue > oldValue && oldValue > 0 {
                DashboardTheme.Animation.withAccessibleAnimation(.easeOut(duration: 0.1)) { eventsFlash = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(800))
                    DashboardTheme.Animation.withAccessibleAnimation(.easeOut(duration: 0.3)) { eventsFlash = false }
                }
            }
        }
        .onChange(of: metrics.errorRate) { oldValue, newValue in
            if newValue > oldValue && newValue > 0 {
                DashboardTheme.Animation.withAccessibleAnimation(.easeOut(duration: 0.1)) { errorFlash = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(800))
                    DashboardTheme.Animation.withAccessibleAnimation(.easeOut(duration: 0.3)) { errorFlash = false }
                }
            }
        }
    }

    private func kpiItem(label: String, value: String, accent: Color? = nil) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(DashboardTheme.Colors.textTertiary)

            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(accent ?? DashboardTheme.Colors.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.standard), value: value)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(DashboardTheme.Colors.borderDefault)
            .frame(width: 1, height: 32)
    }

    private func formattedErrorRate(_ rate: Double) -> String {
        TraceFormatter.errorRate(rate)
    }
}
