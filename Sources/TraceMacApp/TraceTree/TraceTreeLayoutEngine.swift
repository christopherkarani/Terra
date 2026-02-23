import Foundation

/// Horizontal (left-to-right) tree layout for the Trace Tree view.
/// Root positioned at left edge; children branch rightward. Siblings stacked vertically.
enum TraceTreeLayoutEngine {

    // MARK: - Spacing constants

    private static let depthSpacing: CGFloat = 56
    private static let siblingSpacing: CGFloat = 24
    private static let padding: CGFloat = 40

    // MARK: - Node sizes (collapsed) — wider and shorter for horizontal layout

    static func collapsedSize(for kind: FlowNodeKind) -> CGSize {
        switch kind {
        case .agent:      return CGSize(width: 260, height: 56)
        case .inference:  return CGSize(width: 240, height: 48)
        case .tool:       return CGSize(width: 220, height: 44)
        case .stage:      return CGSize(width: 180, height: 36)
        case .embedding:  return CGSize(width: 220, height: 44)
        case .safetyCheck: return CGSize(width: 220, height: 44)
        case .generic:    return CGSize(width: 200, height: 40)
        }
    }

    // MARK: - Expanded height additions (node grows taller when expanded)

    static func expandedHeightAddition(for kind: FlowNodeKind) -> CGFloat {
        switch kind {
        case .inference:  return 200
        case .tool:       return 160
        case .agent:      return 140
        default:          return 120
        }
    }

    // MARK: - Layout

    /// Layout all nodes in a left-to-right tree.
    /// Root at left edge, children branch rightward. Siblings stacked vertically.
    static func layout(
        nodes: [FlowGraphNode],
        nodesByID: [String: FlowGraphNode],
        roots: [String],
        expandedIDs: Set<String>
    ) {
        // 1. Assign sizes based on kind + expansion state
        for node in nodes {
            let base = collapsedSize(for: node.kind)
            if expandedIDs.contains(node.id) {
                let extra = expandedHeightAddition(for: node.kind)
                node.size = CGSize(width: base.width, height: base.height + extra)
            } else {
                node.size = base
            }
        }

        // 2. Compute subtree heights bottom-up (aggregate children vertically)
        var subtreeHeights: [String: CGFloat] = [:]

        func computeSubtreeHeight(_ nodeID: String) -> CGFloat {
            guard let node = nodesByID[nodeID] else { return 0 }

            if node.childIDs.isEmpty {
                let height = node.size.height
                subtreeHeights[nodeID] = height
                return height
            }

            var totalChildrenHeight: CGFloat = 0
            for (index, childID) in node.childIDs.enumerated() {
                totalChildrenHeight += computeSubtreeHeight(childID)
                if index < node.childIDs.count - 1 {
                    totalChildrenHeight += siblingSpacing
                }
            }

            let height = max(node.size.height, totalChildrenHeight)
            subtreeHeights[nodeID] = height
            return height
        }

        for rootID in roots {
            _ = computeSubtreeHeight(rootID)
        }

        // 3. Position nodes left-to-right
        var currentRootY: CGFloat = padding

        func positionNode(_ nodeID: String, x: CGFloat, yCenter: CGFloat) {
            guard let node = nodesByID[nodeID] else { return }

            node.position = CGPoint(
                x: x,
                y: yCenter - node.size.height / 2
            )

            guard !node.childIDs.isEmpty else { return }

            let childX = x + node.size.width + depthSpacing
            let totalChildrenHeight = node.childIDs.enumerated().reduce(CGFloat(0)) { acc, pair in
                let childHeight = subtreeHeights[pair.element] ?? 0
                return acc + childHeight + (pair.offset > 0 ? siblingSpacing : 0)
            }

            var childY = yCenter - totalChildrenHeight / 2

            for childID in node.childIDs {
                let childSubtreeHeight = subtreeHeights[childID] ?? 0
                let childCenter = childY + childSubtreeHeight / 2
                positionNode(childID, x: childX, yCenter: childCenter)
                childY += childSubtreeHeight + siblingSpacing
            }
        }

        for rootID in roots {
            let rootHeight = subtreeHeights[rootID] ?? 0
            let rootCenter = currentRootY + rootHeight / 2
            positionNode(rootID, x: padding, yCenter: rootCenter)
            currentRootY += rootHeight + siblingSpacing * 2
        }
    }
}
