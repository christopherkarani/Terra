import SwiftUI
import TerraTraceKit
import OpenTelemetrySdk

/// The right-column panel showing a hierarchical span tree and
/// tabbed detail view for the selected span.
struct SpanInspectorView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let trace = appState.selectedTrace {
                VSplitView {
                    SpanTreeView(trace: trace)
                        .frame(minHeight: 120)

                    SpanDetailView()
                        .frame(minHeight: 120)
                }
            } else {
                emptyState
            }
        }
        .frame(minWidth: 280)
    }
}

// MARK: - Subviews

private struct EmptyInspectorView: View {
    var body: some View {
        ContentUnavailableView(
            "No Trace Selected",
            systemImage: "text.alignleft",
            description: Text("Select a trace to inspect its spans")
        )
    }
}

private extension SpanInspectorView {
    var emptyState: some View {
        EmptyInspectorView()
    }
}
