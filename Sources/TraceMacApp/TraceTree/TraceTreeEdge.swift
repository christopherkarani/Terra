import SwiftUI

/// A horizontal edge connecting parent (right-center) to child (left-center) in the trace tree.
struct TraceTreeEdge: Identifiable {
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

    /// Thickness: 1.5px default, 2.5px for critical path
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

    /// Horizontal S-curve bezier path: parent right-center -> child left-center.
    /// When aligned (single child), this is nearly a straight line.
    /// When offset (branching), produces a smooth S-curve fork.
    func horizontalBezierPath() -> Path {
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

    /// 6px rightward-pointing arrow head at child entry point
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

    /// Midpoint for edge labels
    var midpoint: CGPoint {
        CGPoint(
            x: (fromPoint.x + toPoint.x) / 2,
            y: (fromPoint.y + toPoint.y) / 2
        )
    }
}
