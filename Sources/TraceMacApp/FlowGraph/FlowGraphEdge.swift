import SwiftUI

/// An edge connecting two nodes in the flow graph.
struct FlowGraphEdge: Identifiable {
    let id: String
    let fromNodeID: String
    let toNodeID: String
    var fromPoint: CGPoint = .zero
    var toPoint: CGPoint = .zero
    var isError: Bool = false
    var isCriticalPath: Bool = false
    var isActive: Bool = false
    var tokenCount: Int?

    init(from: String, to: String) {
        self.id = "\(from)->\(to)"
        self.fromNodeID = from
        self.toNodeID = to
    }

    /// Thickness: 1.5px default, 2.5px for critical path (child duration > 1s)
    var lineWidth: CGFloat {
        isCriticalPath ? 2.5 : 1.5
    }

    /// Edge color: borderStrong default, error edges use accentError at 60%
    var color: Color {
        if isError {
            return DashboardTheme.Colors.accentError.opacity(0.6)
        }
        return DashboardTheme.Colors.borderStrong
    }

    /// Darkened color when either endpoint is hovered
    var hoverColor: Color {
        DashboardTheme.Colors.textTertiary
    }

    /// Horizontal S-curve bezier path via two control points at midX
    func bezierPath() -> Path {
        Path { path in
            let midX = (fromPoint.x + toPoint.x) / 2
            path.move(to: fromPoint)
            path.addCurve(
                to: toPoint,
                control1: CGPoint(x: midX, y: fromPoint.y),
                control2: CGPoint(x: midX, y: toPoint.y)
            )
        }
    }

    /// 6px chevron arrow head at destination point
    func arrowHeadPath() -> Path {
        let size: CGFloat = 6
        let angle = atan2(toPoint.y - fromPoint.y, toPoint.x - fromPoint.x)
        let p1 = CGPoint(
            x: toPoint.x - size * cos(angle - .pi / 6),
            y: toPoint.y - size * sin(angle - .pi / 6)
        )
        let p2 = CGPoint(
            x: toPoint.x - size * cos(angle + .pi / 6),
            y: toPoint.y - size * sin(angle + .pi / 6)
        )
        return Path { path in
            path.move(to: toPoint)
            path.addLine(to: p1)
            path.move(to: toPoint)
            path.addLine(to: p2)
        }
    }

    /// Midpoint of the bezier curve (for edge labels in expanded mode)
    var midpoint: CGPoint {
        let midX = (fromPoint.x + toPoint.x) / 2
        let midY = (fromPoint.y + toPoint.y) / 2
        return CGPoint(x: midX, y: midY)
    }
}
