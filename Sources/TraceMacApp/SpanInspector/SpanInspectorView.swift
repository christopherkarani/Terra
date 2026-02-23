import SwiftUI
import TerraTraceKit
import OpenTelemetrySdk

/// The right-column panel showing the tabbed detail view for the selected span.
/// The tree is now the primary content view, so no redundant tree here.
struct SpanInspectorView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.selectedTrace != nil {
                SpanDetailView()
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
