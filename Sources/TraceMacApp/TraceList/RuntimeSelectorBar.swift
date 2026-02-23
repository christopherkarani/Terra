import SwiftUI
import TerraTraceKit

struct RuntimeSelectorBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                RuntimePill(
                    runtime: .all,
                    count: appState.traces.count,
                    isSelected: appState.runtimeFilter == .all
                ) {
                    appState.runtimeFilter = .all
                }

                ForEach(visibleRuntimes, id: \.runtime) { entry in
                    RuntimePill(
                        runtime: entry.runtime,
                        count: entry.count,
                        isSelected: appState.runtimeFilter == entry.runtime
                    ) {
                        appState.runtimeFilter = entry.runtime
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private var visibleRuntimes: [(runtime: TraceRuntimeFilter, count: Int)] {
        var counts: [TraceRuntimeFilter: Int] = [:]
        for trace in appState.traces {
            let runtime = trace.detectedRuntime
            counts[runtime, default: 0] += 1
        }
        return TraceRuntimeFilter.allCases
            .filter { $0 != .all }
            .compactMap { runtime in
                guard let count = counts[runtime], count > 0 else { return nil }
                return (runtime: runtime, count: count)
            }
    }
}

private struct RuntimePill: View {
    let runtime: TraceRuntimeFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(runtime.accentColor)
                    .frame(width: 6, height: 6)

                Text(runtime.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? DashboardTheme.Colors.textPrimary : DashboardTheme.Colors.textSecondary)

                Text("\(count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DashboardTheme.Colors.textTertiary)
                    .contentTransition(.numericText())
                    .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.standard), value: count)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: DashboardTheme.Spacing.cornerRadius)
                    .fill(isSelected
                        ? DashboardTheme.Colors.accentActive.opacity(0.08)
                        : (isHovered ? DashboardTheme.Colors.surfaceHover : DashboardTheme.Colors.surfaceRaised))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DashboardTheme.Spacing.cornerRadius)
                    .strokeBorder(
                        isSelected ? DashboardTheme.Colors.accentActive.opacity(0.3) : .clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.micro), value: isHovered)
        .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.micro), value: isSelected)
        .accessibilityLabel("\(runtime.title), \(count) traces")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
