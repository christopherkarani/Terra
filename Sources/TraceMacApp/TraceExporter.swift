import AppKit
import Foundation
import OpenTelemetrySdk
import TerraTraceKit
import UniformTypeIdentifiers

enum TraceExporter {
    static func exportTraces(_ traces: [Trace], from window: NSWindow?) {
        guard !traces.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let baseName: String
        if traces.count == 1 {
            let trace = traces[0]
            let sanitized = trace.displayName
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .prefix(60)
            baseName = "trace-\(sanitized).json"
        } else {
            baseName = "traces-export-\(traces.count).json"
        }
        panel.nameFieldStringValue = baseName

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    try writeTracesJSON(traces, to: url)
                } catch {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Could not export traces."
                    alert.informativeText = error.localizedDescription
                    if let window {
                        await alert.beginSheetModal(for: window)
                    } else {
                        alert.runModal()
                    }
                }
            }
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    private static func writeTracesJSON(_ traces: [Trace], to url: URL) throws {
        let allSpans = traces.flatMap(\.spans)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(allSpans)
        try data.write(to: url, options: [.atomic])
    }
}
