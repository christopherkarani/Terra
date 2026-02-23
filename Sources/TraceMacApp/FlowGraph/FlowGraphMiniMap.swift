import SwiftUI

/// Bottom-left overview minimap.
/// 160x100 Canvas: edges as 0.5px gray lines, nodes as 3px dots (colored by type).
/// Viewport rectangle: 1.5px accentActive stroke. Only visible when graph exceeds viewport.
struct FlowGraphMiniMap: View {
    let nodes: [FlowGraphNode]
    let edges: [FlowGraphEdge]
    let contentSize: CGSize
    let viewportSize: CGSize
    let viewportOffset: CGPoint
    let zoomScale: CGFloat

    var body: some View {
        Canvas { context, size in
            let scaleX = size.width / max(contentSize.width, 1)
            let scaleY = size.height / max(contentSize.height, 1)
            let scale = min(scaleX, scaleY)

            // Draw edges as thin gray lines
            for edge in edges {
                let from = CGPoint(x: edge.fromPoint.x * scale, y: edge.fromPoint.y * scale)
                let to = CGPoint(x: edge.toPoint.x * scale, y: edge.toPoint.y * scale)
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                context.stroke(path, with: .color(DashboardTheme.Colors.borderDefault), lineWidth: 0.5)
            }

            // Draw nodes as 3px colored dots
            for node in nodes {
                let x = node.position.x * scale + (node.size.width * scale / 2)
                let y = node.position.y * scale + (node.size.height * scale / 2)
                let rect = CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)
                let color = nodeColor(for: node.kind)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }

            // Viewport rectangle showing current visible area
            let vpX = viewportOffset.x * scale / zoomScale
            let vpY = viewportOffset.y * scale / zoomScale
            let vpW = viewportSize.width * scale / zoomScale
            let vpH = viewportSize.height * scale / zoomScale
            let vpRect = CGRect(x: vpX, y: vpY, width: vpW, height: vpH)
            context.stroke(
                Path(roundedRect: vpRect, cornerRadius: 1),
                with: .color(DashboardTheme.Colors.accentActive),
                lineWidth: 1.5
            )
        }
        .background(DashboardTheme.Colors.windowBackground)
        .clipShape(.rect(cornerRadius: DashboardTheme.Spacing.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTheme.Spacing.cornerRadius)
                .strokeBorder(DashboardTheme.Colors.borderDefault, lineWidth: 1)
        )
    }

    private func nodeColor(for kind: FlowNodeKind) -> Color {
        switch kind {
        case .agent:      return DashboardTheme.Colors.nodeAgent
        case .inference:  return DashboardTheme.Colors.nodeInference
        case .tool:       return DashboardTheme.Colors.nodeTool
        case .stage:      return DashboardTheme.Colors.nodeStage
        case .embedding:  return DashboardTheme.Colors.nodeEmbedding
        case .safetyCheck: return DashboardTheme.Colors.nodeSafety
        case .generic:    return DashboardTheme.Colors.nodeStage
        }
    }
}
