import SwiftUI
import TerraTraceKit
import OpenTelemetrySdk

/// Displays the span hierarchy for a trace as an outline.
struct SpanTreeView: View {
    let trace: Trace
    @Environment(AppState.self) private var appState

    var body: some View {
        let nodes = SpanTreeBuilder.buildTree(from: trace.orderedSpans)

        List(selection: Binding(
            get: { appState.selectedSpan?.spanId.hexString },
            set: { newID in
                if let id = newID,
                   let span = trace.spans.first(where: { $0.spanId.hexString == id }) {
                    appState.selectSpan(span)
                } else {
                    appState.selectSpan(nil)
                }
            }
        )) {
            OutlineGroup(nodes, children: \.outlineChildren) { node in
                SpanTreeRowView(node: node, isSelected: isSelected(node))
                    .tag(node.id)
            }
        }
        .listStyle(.sidebar)
        .scrollIndicators(.hidden)
    }

    private func isSelected(_ node: SpanTreeNode) -> Bool {
        appState.selectedSpan?.spanId.hexString == node.id
    }
}
