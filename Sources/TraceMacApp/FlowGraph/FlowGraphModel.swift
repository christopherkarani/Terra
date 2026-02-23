import Foundation
import SwiftUI
import TerraTraceKit
import OpenTelemetrySdk

/// Observable model that builds and manages the flow graph from a trace.
/// Reuses the same tree-building pattern as SpanTreeBuilder.
@Observable
@MainActor
final class FlowGraphModel: Identifiable {
    let id = UUID()
    var nodes: [FlowGraphNode] = []
    var edges: [FlowGraphEdge] = []
    var selectedNodeID: String?

    private var nodesByID: [String: FlowGraphNode] = [:]
    private var previousSpanIDs: Set<String> = []

    /// Build the complete graph from a trace.
    func build(from trace: Trace) {
        let spans = trace.spans

        // Create nodes from spans
        var newNodes: [FlowGraphNode] = []
        var newNodesByID: [String: FlowGraphNode] = [:]

        for span in spans {
            let node = FlowGraphNode(span: span)
            newNodes.append(node)
            newNodesByID[node.id] = node
        }

        // Build parent-child relationships (group by parentSpanId, find roots)
        let spanIdSet = Set(newNodes.map(\.id))
        for node in newNodes {
            if let parentId = node.parentSpanId, spanIdSet.contains(parentId) {
                newNodesByID[parentId]?.childIDs.append(node.id)
            }
        }

        // Find roots and sort children by startTime
        let roots = newNodes.filter { node in
            guard let parentId = node.parentSpanId else { return true }
            return !spanIdSet.contains(parentId)
        }.sorted { $0.startTime < $1.startTime }

        func assignDepth(_ nodeID: String, depth: Int) {
            guard let node = newNodesByID[nodeID] else { return }
            node.depth = depth
            node.childIDs.sort { a, b in
                let na = newNodesByID[a]?.startTime ?? .distantPast
                let nb = newNodesByID[b]?.startTime ?? .distantPast
                return na < nb
            }
            for childID in node.childIDs {
                assignDepth(childID, depth: depth + 1)
            }
        }

        for root in roots {
            assignDepth(root.id, depth: 0)
        }

        // Layout
        FlowGraphLayoutEngine.layout(nodes: newNodes, nodesByID: newNodesByID, roots: roots.map(\.id))

        // Generate edges
        var newEdges: [FlowGraphEdge] = []
        for node in newNodes {
            for childID in node.childIDs {
                guard let child = newNodesByID[childID] else { continue }
                var edge = FlowGraphEdge(from: node.id, to: childID)
                edge.fromPoint = CGPoint(
                    x: node.position.x + node.size.width,
                    y: node.position.y + node.size.height / 2
                )
                edge.toPoint = CGPoint(
                    x: child.position.x,
                    y: child.position.y + child.size.height / 2
                )
                edge.isError = child.status == .error
                edge.isCriticalPath = child.duration > 1.0
                edge.isActive = child.status == .running
                if child.outputTokens > 0 {
                    edge.tokenCount = child.outputTokens
                }
                newEdges.append(edge)
            }
        }

        self.nodes = newNodes
        self.edges = newEdges
        self.nodesByID = newNodesByID
        self.previousSpanIDs = Set(spans.map { $0.spanId.hexString })
    }

    /// Incremental insert for real-time streaming.
    func addSpan(_ span: SpanData) {
        let spanID = span.spanId.hexString
        guard !previousSpanIDs.contains(spanID) else { return }
        previousSpanIDs.insert(spanID)

        let node = FlowGraphNode(span: span)
        nodes.append(node)
        nodesByID[node.id] = node

        if let parentId = node.parentSpanId, let parent = nodesByID[parentId] {
            parent.childIDs.append(node.id)
            node.depth = parent.depth + 1
        }

        rebuildLayout()
    }

    /// Status change on existing node.
    func updateSpan(_ span: SpanData) {
        let spanID = span.spanId.hexString
        guard let node = nodesByID[spanID] else { return }

        if span.status.isError {
            node.status = .error
        } else if span.endTime > span.startTime {
            node.status = .completed
        }
    }

    func node(for id: String) -> FlowGraphNode? {
        nodesByID[id]
    }

    /// Total content size for scroll view.
    var contentSize: CGSize {
        guard !nodes.isEmpty else { return CGSize(width: 400, height: 300) }
        let maxX = nodes.map { $0.position.x + $0.size.width }.max() ?? 400
        let maxY = nodes.map { $0.position.y + $0.size.height }.max() ?? 300
        return CGSize(width: maxX + 60, height: maxY + 60)
    }

    func rebuildLayout() {
        let spanIdSet = Set(nodes.map(\.id))
        let roots = nodes.filter { node in
            guard let parentId = node.parentSpanId else { return true }
            return !spanIdSet.contains(parentId)
        }.sorted { $0.startTime < $1.startTime }

        FlowGraphLayoutEngine.layout(nodes: nodes, nodesByID: nodesByID, roots: roots.map(\.id))

        // Rebuild edges
        var newEdges: [FlowGraphEdge] = []
        for node in nodes {
            for childID in node.childIDs {
                guard let child = nodesByID[childID] else { continue }
                var edge = FlowGraphEdge(from: node.id, to: childID)
                edge.fromPoint = CGPoint(
                    x: node.position.x + node.size.width,
                    y: node.position.y + node.size.height / 2
                )
                edge.toPoint = CGPoint(
                    x: child.position.x,
                    y: child.position.y + child.size.height / 2
                )
                edge.isError = child.status == .error
                edge.isCriticalPath = child.duration > 1.0
                edge.isActive = child.status == .running
                if child.outputTokens > 0 {
                    edge.tokenCount = child.outputTokens
                }
                newEdges.append(edge)
            }
        }
        self.edges = newEdges
    }
}
