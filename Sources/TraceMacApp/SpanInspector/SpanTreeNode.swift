import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

/// A node in the span tree hierarchy, used for displaying spans
/// in a parent-child outline structure.
struct SpanTreeNode: Identifiable {
    let id: String
    let span: SpanData
    let children: [SpanTreeNode]
    let depth: Int
    let durationFraction: Double

    /// Returns children for `OutlineGroup`, nil when empty.
    var outlineChildren: [SpanTreeNode]? {
        children.isEmpty ? nil : children
    }
}

/// Builds a tree of `SpanTreeNode` values from a flat list of spans,
/// using `parentSpanId` to establish parent-child relationships.
enum SpanTreeBuilder {
    static func buildTree(from spans: [SpanData]) -> [SpanTreeNode] {
        let traceDuration = computeTraceDuration(spans: spans)
        let spanIds = Set(spans.map(\.spanId))
        let childrenByParent = Dictionary(grouping: spans) { $0.parentSpanId }

        let roots = spans.filter { span in
            guard let parent = span.parentSpanId else { return true }
            return !spanIds.contains(parent)
        }.sorted { $0.startTime < $1.startTime }

        return roots.map { buildNode(span: $0, depth: 0, childrenByParent: childrenByParent, traceDuration: traceDuration) }
    }

    private static func computeTraceDuration(spans: [SpanData]) -> TimeInterval {
        guard let earliest = spans.min(by: { $0.startTime < $1.startTime }),
              let latest = spans.max(by: { $0.endTime < $1.endTime }) else {
            return 1
        }
        return max(latest.endTime.timeIntervalSince(earliest.startTime), 0.001)
    }

    private static func buildNode(
        span: SpanData,
        depth: Int,
        childrenByParent: [SpanId?: [SpanData]],
        traceDuration: TimeInterval
    ) -> SpanTreeNode {
        let childSpans = (childrenByParent[span.spanId] ?? [])
            .sorted { $0.startTime < $1.startTime }

        let childNodes = childSpans.map {
            buildNode(span: $0, depth: depth + 1, childrenByParent: childrenByParent, traceDuration: traceDuration)
        }

        let spanDuration = span.endTime.timeIntervalSince(span.startTime)
        let fraction = max(0, min(1, spanDuration / traceDuration))

        return SpanTreeNode(
            id: span.spanId.hexString,
            span: span,
            children: childNodes,
            depth: depth,
            durationFraction: fraction
        )
    }
}
