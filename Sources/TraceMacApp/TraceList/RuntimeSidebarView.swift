import SwiftUI
import TerraTraceKit

/// Left sidebar: groups traces by runtime with aggregated stats and expandable trace lists.
struct RuntimeSidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groupedRuntimes, id: \.runtime) { group in
                        RuntimeGroupRow(
                            group: group,
                            isExpanded: appState.expandedRuntimes.contains(group.runtime),
                            selectedTraceId: appState.selectedTrace?.id,
                            onToggle: { toggleRuntime(group.runtime) },
                            onSelectTrace: { trace in appState.selectTrace(trace) }
                        )
                    }
                }
                .padding(.vertical, DashboardTheme.Spacing.md)
            }

            Divider()

            ConnectionStatusBar()
        }
        .frame(maxHeight: .infinity)
        .background(DashboardTheme.Colors.sidebarBackground)
    }

    private var sidebarHeader: some View {
        HStack {
            Text("RUNTIMES")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(DashboardTheme.Colors.textTertiary)
            Spacer()
            Text("\(appState.filteredTraces.count)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(DashboardTheme.Colors.textQuaternary)
        }
        .padding(.horizontal, DashboardTheme.Spacing.lg)
        .padding(.vertical, DashboardTheme.Spacing.md)
    }

    private var groupedRuntimes: [RuntimeGroup] {
        let traces = appState.filteredTraces
        let grouped = Dictionary(grouping: traces) { $0.detectedRuntime }
        return grouped.map { runtime, traces in
            let metrics = DashboardViewModel.compute(from: traces)
            return RuntimeGroup(
                runtime: runtime,
                traces: traces.sorted { $0.fileTimestamp > $1.fileTimestamp },
                metrics: metrics
            )
        }
        .sorted { $0.traces.count > $1.traces.count }
    }

    private func toggleRuntime(_ runtime: TraceRuntimeFilter) {
        @Bindable var appState = appState
        DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
            if appState.expandedRuntimes.contains(runtime) {
                appState.expandedRuntimes.remove(runtime)
            } else {
                appState.expandedRuntimes.insert(runtime)
            }
        }
    }
}

// MARK: - Data Model

struct RuntimeGroup {
    let runtime: TraceRuntimeFilter
    let traces: [Trace]
    let metrics: DashboardMetrics
}

// MARK: - Runtime Group Row

private struct RuntimeGroupRow: View {
    let group: RuntimeGroup
    let isExpanded: Bool
    let selectedTraceId: String?
    let onToggle: () -> Void
    let onSelectTrace: (Trace) -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Disclosure header
            Button(action: onToggle) {
                HStack(spacing: DashboardTheme.Spacing.md) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(DashboardTheme.Colors.textQuaternary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.standard), value: isExpanded)
                        .frame(width: 10)

                    Circle()
                        .fill(group.runtime.accentColor)
                        .frame(width: 8, height: 8)

                    Text(group.runtime.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DashboardTheme.Colors.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text("\(group.traces.count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(DashboardTheme.Colors.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DashboardTheme.Colors.surfaceRaised)
                        .clipShape(.capsule)
                }
                .padding(.horizontal, DashboardTheme.Spacing.lg)
                .padding(.vertical, 6)
                .background(isHovered ? DashboardTheme.Colors.surfaceHover : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .accessibilityLabel("\(group.runtime.title), \(group.traces.count) traces")
            .accessibilityHint(isExpanded ? "Collapse group" : "Expand group")

            // Stats row
            HStack(spacing: DashboardTheme.Spacing.md) {
                statLabel("p50", TraceFormatter.duration(group.metrics.p50Duration))
                statLabel("err", TraceFormatter.errorRate(group.metrics.errorRate), isError: group.metrics.errorRate > 0)
                if group.metrics.ttftP50 > 0 {
                    statLabel("TTFT", TraceFormatter.duration(group.metrics.ttftP50))
                }
            }
            .padding(.horizontal, DashboardTheme.Spacing.lg)
            .padding(.leading, 22)
            .padding(.bottom, 4)

            // Expanded trace list
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.horizontal, DashboardTheme.Spacing.lg)

                    ForEach(group.traces.prefix(20), id: \.id) { trace in
                        CompactTraceRow(
                            trace: trace,
                            isSelected: selectedTraceId == trace.id,
                            onTap: { onSelectTrace(trace) }
                        )
                    }

                    if group.traces.count > 20 {
                        Text("+\(group.traces.count - 20) more")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(DashboardTheme.Colors.textQuaternary)
                            .padding(.horizontal, DashboardTheme.Spacing.lg)
                            .padding(.vertical, 4)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()
                .padding(.horizontal, DashboardTheme.Spacing.lg)
        }
    }

    private func statLabel(_ label: String, _ value: String, isError: Bool = false) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DashboardTheme.Colors.textQuaternary)
            Text(value)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(isError ? DashboardTheme.Colors.accentError : DashboardTheme.Colors.textTertiary)
        }
    }
}

// MARK: - Compact Trace Row

private struct CompactTraceRow: View {
    let trace: Trace
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DashboardTheme.Spacing.md) {
                Text(trace.displayName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(DashboardTheme.Colors.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text(TraceFormatter.duration(trace.duration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DashboardTheme.Colors.textTertiary)
            }
            .padding(.horizontal, DashboardTheme.Spacing.lg)
            .padding(.leading, 22)
            .padding(.vertical, 4)
            .background(isSelected ? DashboardTheme.Colors.surfaceActive : (isHovered ? DashboardTheme.Colors.surfaceHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
