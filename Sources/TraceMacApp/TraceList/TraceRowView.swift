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
                    if trace.detectedRuntime != .other {
                        Text(trace.detectedRuntime.title)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(runtimeForeground)
                            .background(runtimeBackground)
                            .clipShape(.capsule)
                    }
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

    private var runtimeForeground: Color {
        switch trace.detectedRuntime {
        case .coreML, .foundationModels:
            return .purple
        case .mlx:
            return .blue
        case .ollama:
            return .orange
        case .lmStudio:
            return .indigo
        case .llamaCpp:
            return .teal
        case .openClawGateway:
            return DashboardTheme.Colors.accentSuccess
        case .httpAPI:
            return DashboardTheme.Colors.accentWarning
        case .other:
            return DashboardTheme.Colors.textSecondary
        case .all:
            return DashboardTheme.Colors.textSecondary
        }
    }

    private var runtimeBackground: Color {
        switch trace.detectedRuntime {
        case .coreML, .foundationModels:
            return Color.purple.opacity(0.12)
        case .mlx:
            return Color.blue.opacity(0.12)
        case .ollama:
            return Color.orange.opacity(0.12)
        case .lmStudio:
            return Color.indigo.opacity(0.12)
        case .llamaCpp:
            return Color.teal.opacity(0.12)
        case .openClawGateway:
            return DashboardTheme.Colors.accentSuccess.opacity(0.15)
        case .httpAPI:
            return DashboardTheme.Colors.accentWarning.opacity(0.15)
        case .other, .all:
            return DashboardTheme.Colors.textTertiary.opacity(0.12)
        }
    }
}
