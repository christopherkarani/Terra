import SwiftUI

struct ConnectionStatusBar: View {
    @Environment(AppState.self) private var appState
    @State private var lastReceivedText: String = ""
    @State private var otlpPulse: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(DashboardTheme.Colors.borderDefault)
                .frame(height: 1)

            HStack(spacing: 8) {
                // OTLP status
                HStack(spacing: 4) {
                    Circle()
                        .fill(appState.isOTLPReceiverRunning
                            ? DashboardTheme.Colors.accentSuccess
                            : DashboardTheme.Colors.textQuaternary)
                        .frame(width: 5, height: 5)
                        .scaleEffect(otlpPulse ? 1.6 : 1.0)
                        .animation(.easeOut(duration: 0.4), value: otlpPulse)

                    if appState.isOTLPReceiverRunning {
                        Text("OTLP :\(AppSettings.otlpReceiverPort)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(DashboardTheme.Colors.textTertiary)
                    } else {
                        Text("OTLP off")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(DashboardTheme.Colors.textQuaternary)
                    }
                }

                // Watcher status
                HStack(spacing: 4) {
                    Circle()
                        .fill(appState.isFileWatcherRunning
                            ? DashboardTheme.Colors.accentSuccess
                            : DashboardTheme.Colors.textQuaternary)
                        .frame(width: 5, height: 5)

                    Text(appState.isFileWatcherRunning ? "Watching" : "Idle")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(DashboardTheme.Colors.textTertiary)
                }

                if !lastReceivedText.isEmpty {
                    Rectangle()
                        .fill(DashboardTheme.Colors.textQuaternary)
                        .frame(width: 1, height: 8)

                    Text("Last: \(lastReceivedText)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(DashboardTheme.Colors.textTertiary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .background(DashboardTheme.Colors.sidebarBackground)
        .task {
            updateLastReceived()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                updateLastReceived()
            }
        }
        .onChange(of: appState.lastTraceReceivedAt) { _, _ in
            updateLastReceived()
            // Pulse the OTLP dot
            otlpPulse = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                otlpPulse = false
            }
        }
    }

    private func updateLastReceived() {
        guard let date = appState.lastTraceReceivedAt else {
            lastReceivedText = ""
            return
        }
        lastReceivedText = TraceFormatter.relativeTime(date)
    }
}
