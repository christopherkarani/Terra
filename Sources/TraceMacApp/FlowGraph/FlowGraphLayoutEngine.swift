import Foundation

/// Modified Walker tree layout — left-to-right orientation.
/// Time flows left→right matching widescreen monitors.
enum FlowGraphLayoutEngine {

    // Node sizes by kind, growing with reveal phase
    static func nodeSize(for kind: FlowNodeKind, phase: RevealPhase = .complete) -> CGSize {
        let baseSize: CGSize = switch kind {
        case .agent:      CGSize(width: 200, height: 80)
        case .inference:  CGSize(width: 180, height: 64)
        case .tool:       CGSize(width: 160, height: 56)
        case .embedding:  CGSize(width: 160, height: 56)
        case .safetyCheck: CGSize(width: 160, height: 56)
        case .stage:      CGSize(width: 120, height: 40)
        case .generic:    CGSize(width: 140, height: 48)
        }
        let phaseGrowth: CGFloat = switch phase {
        case .started:   0
        case .metrics:   16
        case .streaming: 32
        case .complete:  48
        }
        return CGSize(width: baseSize.width, height: baseSize.height + phaseGrowth)
    }

    /// Spacing: 60px horizontal between depth levels, 24px vertical between siblings
    private static let horizontalSpacing: CGFloat = 60
    private static let verticalSpacing: CGFloat = 24
    private static let padding: CGFloat = 40

    /// Layout all nodes using a left-to-right tree layout.
    /// Parent centered vertically over children span.
    static func layout(
        nodes: [FlowGraphNode],
        nodesByID: [String: FlowGraphNode],
        roots: [String]
    ) {
        // Assign sizes (phase-aware)
        for node in nodes {
            node.size = nodeSize(for: node.kind, phase: node.revealPhase)
        }

        // Calculate subtree heights (bottom-up)
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
                    totalChildrenHeight += verticalSpacing
                }
            }

            let height = max(node.size.height, totalChildrenHeight)
            subtreeHeights[nodeID] = height
            return height
        }

        for rootID in roots {
            _ = computeSubtreeHeight(rootID)
        }

        // Position nodes (left-to-right)
        var currentRootY: CGFloat = padding

        func positionNode(_ nodeID: String, x: CGFloat, yCenter: CGFloat) {
            guard let node = nodesByID[nodeID] else { return }

            node.position = CGPoint(
                x: x,
                y: yCenter - node.size.height / 2
            )

            guard !node.childIDs.isEmpty else { return }

            let childX = x + node.size.width + horizontalSpacing
            let totalChildrenHeight = node.childIDs.enumerated().reduce(CGFloat(0)) { acc, pair in
                let childHeight = subtreeHeights[pair.element] ?? 0
                return acc + childHeight + (pair.offset > 0 ? verticalSpacing : 0)
            }

            var childY = yCenter - totalChildrenHeight / 2

            for childID in node.childIDs {
                let childSubtreeHeight = subtreeHeights[childID] ?? 0
                let childCenter = childY + childSubtreeHeight / 2
                positionNode(childID, x: childX, yCenter: childCenter)
                childY += childSubtreeHeight + verticalSpacing
            }
        }

        for rootID in roots {
            let rootHeight = subtreeHeights[rootID] ?? 0
            let rootCenter = currentRootY + rootHeight / 2
            positionNode(rootID, x: padding, yCenter: rootCenter)
            currentRootY += rootHeight + verticalSpacing * 2
        }
    }
}
