import AppKit
import SwiftUI

struct AppStateFocusedKey: FocusedValueKey {
    typealias Value = AppState
}

extension FocusedValues {
    var appState: AppState? {
        get { self[AppStateFocusedKey.self] }
        set { self[AppStateFocusedKey.self] = newValue }
    }
}

struct TraceCommands: Commands {
    @FocusedValue(\.appState) private var appState

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Reload Traces") {
                appState?.loadTraces()
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Load Sample Traces") {
                appState?.loadSampleTraces()
            }

            Divider()

            Button("Export Selected Trace\u{2026}") {
                appState?.exportSelectedTrace(from: NSApp.keyWindow)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(appState?.selectedTrace == nil)

            Button("Export All Traces\u{2026}") {
                appState?.exportAllTraces(from: NSApp.keyWindow)
            }
            .disabled(appState?.traces.isEmpty ?? true)

            Divider()

            Button("Choose Traces Folder\u{2026}") {
                appState?.chooseTracesFolder()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("Setup OpenClaw Tracing") {
                appState?.setupOpenClawTracing()
            }

            Button("Use OpenClaw Diagnostics Folder") {
                appState?.useOpenClawDiagnosticsFolder()
            }

            Button("Install OpenClaw diagnostics-otel Plugin") {
                appState?.installOpenClawDiagnosticsPlugin()
            }

            Button("Open Traces Folder in Finder") {
                appState?.openTracesFolder()
            }

            Divider()

            if appState?.isOTLPReceiverRunning == true {
                Button("Stop OTLP Receiver") {
                    appState?.stopOTLPReceiver()
                }
            } else {
                Button("Start OTLP Receiver (Port \(AppSettings.otlpReceiverPort))") {
                    appState?.startOTLPReceiver()
                }
            }

            Divider()

            Button("Open OpenClaw Logging Guide") {
                appState?.openOpenClawLoggingGuide()
            }

            Button("Open OpenClaw Plugin Guide") {
                appState?.openOpenClawPluginGuide()
            }
        }
    }
}
