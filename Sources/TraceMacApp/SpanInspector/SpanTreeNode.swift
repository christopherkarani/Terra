import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

/// A node in the span tree hierarchy, used for displaying spans
/// in a parent-child outline structure.
struct SpanTreeNode: Identifiable {
    let id: String
    let span: SpanData
    let children: [SpanTreeNode]

    /// Returns children for `OutlineGroup`, nil when empty.
    var outlineChildren: [SpanTreeNode]? {
        children.isEmpty ? nil : children
    }
    let depth: Int
}

/// Builds a tree of `SpanTreeNode` values from a flat list of spans,
/// using `parentSpanId` to establish parent-child relationships.
enum SpanTreeBuilder {
    static func buildTree(from spans: [SpanData]) -> [SpanTreeNode] {
        let spanIds = Set(spans.map(\.spanId))
        let childrenByParent = Dictionary(grouping: spans) { $0.parentSpanId }

        let roots = spans.filter { span in
            guard let parent = span.parentSpanId else { return true }
            return !spanIds.contains(parent)
        }.sorted { $0.startTime < $1.startTime }

        return roots.map { buildNode(span: $0, depth: 0, childrenByParent: childrenByParent) }
    }

    private static func buildNode(
        span: SpanData,
        depth: Int,
        childrenByParent: [SpanId?: [SpanData]]
    ) -> SpanTreeNode {
        let childSpans = (childrenByParent[span.spanId] ?? [])
            .sorted { $0.startTime < $1.startTime }

        let childNodes = childSpans.map {
            buildNode(span: $0, depth: depth + 1, childrenByParent: childrenByParent)
        }

        return SpanTreeNode(
            id: span.spanId.hexString,
            span: span,
            children: childNodes,
            depth: depth
        )
    }
}
