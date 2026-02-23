import SwiftUI
import TerraTraceKit

/// Main flow graph view — hybrid Canvas (edges) + SwiftUI overlay (nodes).
/// The hero view of Terra.
struct TraceFlowGraphView: View {
    let flowModel: FlowGraphModel
    var onSelectSpan: ((String) -> Void)? = nil

    @State private var zoomScale: CGFloat = 1.0
    @State private var hoveredNodeID: String?
    @State private var tooltipNodeID: String?
    @State private var tooltipTimer: Timer?
    @State private var scrollOffset: CGPoint = .zero
    @State private var visibleNodeIDs: Set<String> = []
    @State private var entranceComplete = false
    @State private var viewportSize: CGSize = .zero

    private let minZoom: CGFloat = 0.25
    private let maxZoom: CGFloat = 4.0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            scrollableContent

            // Controls overlay (bottom-right)
            FlowGraphControls(
                zoomScale: $zoomScale,
                minZoom: minZoom,
                maxZoom: maxZoom,
                isExpanded: zoomScale > 1.5,
                onFitToView: fitToView
            )
            .padding(12)

            // Minimap (bottom-left) — only when graph exceeds viewport
            if flowModel.contentSize.width > 600 || flowModel.contentSize.height > 400 {
                FlowGraphMiniMap(
                    nodes: flowModel.nodes,
                    edges: flowModel.edges,
                    contentSize: flowModel.contentSize,
                    viewportSize: viewportSize,
                    viewportOffset: scrollOffset,
                    zoomScale: zoomScale
                )
                .frame(width: 160, height: 100)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }

            // Tooltip
            if let tooltipNodeID, let node = flowModel.node(for: tooltipNodeID) {
                FlowNodeTooltipView(node: node)
                    .position(tooltipPosition(for: node))
                    .transition(.opacity)
                    .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.micro), value: tooltipNodeID)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ViewportSizeKey.self, value: geo.size)
            }
        )
        .onPreferenceChange(ViewportSizeKey.self) { viewportSize = $0 }
        .background(DashboardTheme.Colors.windowBackground)
        .clipped()
        .onKeyPress(characters: .init(charactersIn: "=+")) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                zoomScale = min(zoomScale + 0.25, maxZoom)
            }
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "-")) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                zoomScale = max(zoomScale - 0.25, minZoom)
            }
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "0")) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                zoomScale = 1.0
            }
            return .handled
        }
        .task(id: flowModel.id) {
            await staggerNodeEntrance()
        }
    }

    private func fitToView() {
        let content = flowModel.contentSize
        guard content.width > 0, content.height > 0,
              viewportSize.width > 0, viewportSize.height > 0 else { return }
        let scale = min(viewportSize.width / content.width, viewportSize.height / content.height)
        DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
            zoomScale = min(max(scale, minZoom), maxZoom)
        }
    }

    /// Reveal nodes depth-by-depth with 80ms delay per level.
    private func staggerNodeEntrance() async {
        visibleNodeIDs.removeAll()
        entranceComplete = false
        let maxDepth = flowModel.nodes.map(\.depth).max() ?? 0
        for depth in 0...maxDepth {
            let nodesAtDepth = flowModel.nodes.filter { $0.depth == depth }.map(\.id)
            DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.entrance) {
                visibleNodeIDs.formUnion(nodesAtDepth)
            }
            try? await Task.sleep(for: .milliseconds(80))
        }
        entranceComplete = true
    }

    // MARK: - Scrollable Content

    private var scrollableContent: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                // Canvas layer: draws bezier edges (non-interactive, high-performance)
                Canvas { context, size in
                    for edge in flowModel.edges {
                        let path = edge.bezierPath()
                        let isHighlighted = hoveredNodeID == edge.fromNodeID || hoveredNodeID == edge.toNodeID
                        let strokeColor = isHighlighted ? edge.hoverColor : edge.color

                        // Critical path glow: wider 20%-opacity stroke behind main stroke
                        if edge.isCriticalPath {
                            context.stroke(
                                path,
                                with: .color(strokeColor.opacity(0.2)),
                                lineWidth: edge.lineWidth * 3
                            )
                        }

                        if edge.isActive {
                            // Dashed stroke for streaming/in-progress edges
                            context.stroke(
                                path,
                                with: .color(strokeColor),
                                style: StrokeStyle(lineWidth: edge.lineWidth, dash: [6, 4])
                            )
                        } else {
                            context.stroke(
                                path,
                                with: .color(strokeColor),
                                lineWidth: edge.lineWidth
                            )
                        }

                        // Arrow head (6px chevron at destination)
                        let arrowPath = edge.arrowHeadPath()
                        context.stroke(
                            arrowPath,
                            with: .color(strokeColor),
                            lineWidth: edge.lineWidth
                        )

                        // Token count label at edge midpoint (only when zoomed in)
                        if zoomScale > 1.0, let tokenCount = edge.tokenCount {
                            let label = Text("\(tokenCount) tok")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(DashboardTheme.Colors.textSecondary)
                            let resolved = context.resolve(label)
                            let labelSize = resolved.measure(in: size)
                            let mid = edge.midpoint
                            let pillRect = CGRect(
                                x: mid.x - labelSize.width / 2 - 4,
                                y: mid.y - labelSize.height / 2 - 2,
                                width: labelSize.width + 8,
                                height: labelSize.height + 4
                            )
                            context.fill(
                                Path(roundedRect: pillRect, cornerRadius: 3),
                                with: .color(DashboardTheme.Colors.surfaceRaised)
                            )
                            context.draw(resolved, at: CGPoint(x: mid.x, y: mid.y))
                        }
                    }
                }
                .frame(
                    width: flowModel.contentSize.width * zoomScale,
                    height: flowModel.contentSize.height * zoomScale
                )

                // SwiftUI overlay: ForEach of FlowNodeView positioned at computed coordinates
                ForEach(flowModel.nodes) { node in
                    FlowNodeView(
                        node: node,
                        isSelected: flowModel.selectedNodeID == node.id,
                        isExpanded: zoomScale > 1.5,
                        onTap: {
                            flowModel.selectedNodeID = node.id
                            onSelectSpan?(node.spanId)
                        }
                    )
                    .position(
                        x: (node.position.x + node.size.width / 2) * zoomScale,
                        y: (node.position.y + node.size.height / 2) * zoomScale
                    )
                    .scaleEffect(zoomScale)
                    // Staggered entrance: nodes appear by depth level
                    .opacity(visibleNodeIDs.contains(node.id) || entranceComplete ? 1 : 0)
                    .scaleEffect(visibleNodeIDs.contains(node.id) || entranceComplete ? 1 : 0.85)
                    .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.entrance), value: visibleNodeIDs.contains(node.id))
                    .onHover { hovering in
                        hoveredNodeID = hovering ? node.id : nil
                        handleTooltipHover(nodeID: node.id, isHovering: hovering)
                    }
                }
            }
            .frame(
                width: flowModel.contentSize.width * zoomScale,
                height: flowModel.contentSize.height * zoomScale
            )
        }
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    let newScale = zoomScale * value.magnification
                    zoomScale = min(max(newScale, minZoom), maxZoom)
                }
        )
    }

    // MARK: - Tooltip

    private func handleTooltipHover(nodeID: String, isHovering: Bool) {
        tooltipTimer?.invalidate()
        if isHovering {
            // 400ms hover delay to prevent tooltip flicker
            tooltipTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
                Task { @MainActor in
                    withAnimation {
                        tooltipNodeID = nodeID
                    }
                }
            }
        } else {
            withAnimation {
                tooltipNodeID = nil
            }
        }
    }

    /// Position tooltip to the right of the node; flip left if near right edge.
    private func tooltipPosition(for node: FlowGraphNode) -> CGPoint {
        let tooltipWidth: CGFloat = 220
        let tooltipOffset: CGFloat = 10
        let nodeRight = (node.position.x + node.size.width) * zoomScale
        let contentWidth = flowModel.contentSize.width * zoomScale

        // Flip left if tooltip would overflow the content area
        let x: CGFloat
        if nodeRight + tooltipOffset + tooltipWidth > contentWidth {
            x = (node.position.x - tooltipWidth / 2 - tooltipOffset) * zoomScale
        } else {
            x = (node.position.x + node.size.width + tooltipWidth / 2 + tooltipOffset) * zoomScale
        }

        return CGPoint(
            x: x,
            y: (node.position.y + node.size.height / 2) * zoomScale
        )
    }
}

private struct ViewportSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
