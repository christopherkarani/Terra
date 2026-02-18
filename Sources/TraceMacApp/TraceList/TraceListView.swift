import SwiftUI
import TerraTraceKit

struct TraceListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 8) {
            OpenClawSetupCard()
                .padding(.horizontal, 8)
                .padding(.top, 8)

            List(selection: Binding(
                get: { appState.selectedTrace?.id },
                set: { newID in
                    let trace = appState.filteredTraces.first { $0.id == newID }
                    appState.selectTrace(trace)
                }
            )) {
                Section {
                    ForEach(appState.filteredTraces, id: \.id) { trace in
                        TraceRowView(trace: trace)
                            .tag(trace.id)
                    }
                } header: {
                    Text("\(appState.filteredTraces.count) Traces")
                        .font(DashboardTheme.sectionHeader)
                }
            }
            .searchable(text: $appState.searchQuery)
            .padding(.top, -4)
        }
    }
}

private struct OpenClawSetupCard: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("OpenClaw Tracing", systemImage: "waveform.path.ecg")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                OpenClawSetupBadge(status: appState.openClawSetupStatus)
            }

            Text(appState.openClawSetupDescription)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(appState.openClawPluginStatusText)
                .font(.system(size: 11))
                .foregroundStyle(pluginStatusColor)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Button("Quick Setup") {
                    appState.setupOpenClawTracing()
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(appState.openClawPluginStatus == .installing)

                Button("Install Plugin") {
                    appState.installOpenClawDiagnosticsPlugin()
                }
                .disabled(appState.openClawPluginStatus == .installing)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(DashboardTheme.surfaceBackground)
        )
    }

    private var pluginStatusColor: Color {
        switch appState.openClawPluginStatus {
        case .installed:
            return DashboardTheme.Colors.accentSuccess
        case .failed:
            return DashboardTheme.Colors.accentError
        case .unknown, .installing:
            return DashboardTheme.Colors.textSecondary
        }
    }
}

private struct OpenClawSetupBadge: View {
    let status: AppState.OpenClawSetupStatus

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background)
            .clipShape(.capsule)
    }

    private var text: String {
        switch status {
        case .notConnected:
            return "Not Connected"
        case .waitingForDiagnostics:
            return "Waiting"
        case .connected:
            return "Connected"
        }
    }

    private var foreground: Color {
        switch status {
        case .connected:
            return DashboardTheme.Colors.accentSuccess
        case .waitingForDiagnostics:
            return DashboardTheme.Colors.accentWarning
        case .notConnected:
            return DashboardTheme.Colors.textSecondary
        }
    }

    private var background: Color {
        switch status {
        case .connected:
            return DashboardTheme.Colors.accentSuccess.opacity(0.12)
        case .waitingForDiagnostics:
            return DashboardTheme.Colors.accentWarning.opacity(0.12)
        case .notConnected:
            return DashboardTheme.Colors.textTertiary.opacity(0.12)
        }
    }
}
