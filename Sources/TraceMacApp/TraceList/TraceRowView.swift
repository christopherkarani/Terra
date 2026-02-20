import SwiftUI
import TerraTraceKit

struct TraceRowView: View {
    let trace: Trace

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(trace.hasError ? DashboardTheme.accentError : .green)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(trace.displayName)
                    .font(DashboardTheme.rowTitle)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if trace.openClawSource != .other {
                        Text(trace.openClawSource.title)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(sourceForeground)
                            .background(sourceBackground)
                            .clipShape(.capsule)
                    }
                    Text(TraceFormatter.duration(trace.duration))
                    Text(TraceFormatter.timestamp(trace.fileTimestamp))
                }
                .font(DashboardTheme.rowMeta)
                .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
    }

    private var sourceForeground: Color {
        switch trace.openClawSource {
        case .gateway:
            return DashboardTheme.Colors.accentSuccess
        case .diagnostics:
            return DashboardTheme.Colors.accentWarning
        case .other:
            return DashboardTheme.Colors.textSecondary
        }
    }

    private var sourceBackground: Color {
        switch trace.openClawSource {
        case .gateway:
            return DashboardTheme.Colors.accentSuccess.opacity(0.15)
        case .diagnostics:
            return DashboardTheme.Colors.accentWarning.opacity(0.15)
        case .other:
            return DashboardTheme.Colors.textTertiary.opacity(0.12)
        }
    }
}
