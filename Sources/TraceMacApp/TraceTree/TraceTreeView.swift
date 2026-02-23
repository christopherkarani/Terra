import SwiftUI
import TerraTraceKit
import OpenTelemetrySdk

/// Horizontal trace tree — left-to-right node graph with expandable detail cards.
/// Uses the same Canvas + SwiftUI overlay architecture as TraceFlowGraphView.
struct TraceTreeView: View {
    let trace: Trace
    var onSelectSpan: ((String) -> Void)? = nil

    // MARK: - State

    @State private var nodes: [FlowGraphNode] = []
    @State private var nodesByID: [String: FlowGraphNode] = [:]
    @State private var spansByNodeID: [String: SpanData] = [:]
    @State private var edges: [TraceTreeEdge] = []
    @State private var roots: [String] = []
    @State private var expandedNodeIDs: Set<String> = []
    @State private var selectedNodeID: String?
    @State private var hoveredNodeID: String?
    @State private var zoomScale: CGFloat = 1.0
    @State private var visibleNodeIDs: Set<String> = []
    @State private var entranceComplete = false
    @State private var edgeProgress: [String: CGFloat] = [:]
    @State private var dashPhase: CGFloat = 0
    @State private var viewportSize: CGSize = .zero
    @State private var layoutGeneration: Int = 0  // Incremented on relayout to force Canvas redraw
    @State private var autoFollowEnabled = true
    @State private var userHasScrolled = false

    private let minZoom: CGFloat = 0.25
    private let maxZoom: CGFloat = 4.0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            scrollableContent

            // Controls (bottom-right)
            VStack(spacing: DashboardTheme.Spacing.sm) {
                // Jump to latest button (shown when auto-follow is off and streaming)
                if !autoFollowEnabled && hasRunningNodes {
                    jumpToLatestButton
                }

                zoomControls
            }
            .padding(12)
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: TreeViewportSizeKey.self, value: geo.size)
            }
        )
        .onPreferenceChange(TreeViewportSizeKey.self) { viewportSize = $0 }
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
        .task(id: trace.id) {
            buildGraph()
            await staggerNodeEntrance()
        }
        .onChange(of: trace.spans.count) { oldCount, newCount in
            guard newCount != oldCount, newCount > 0 else { return }
            incrementalUpdate()
        }
        .onChange(of: expandedNodeIDs) { _, _ in
            relayout()
        }
    }

    // MARK: - Computed

    private var hasRunningNodes: Bool {
        nodes.contains { $0.status == .running }
    }

    // MARK: - Graph Building

    private func buildGraph() {
        let spans = trace.spans

        var newNodes: [FlowGraphNode] = []
        var newNodesByID: [String: FlowGraphNode] = [:]
        var newSpansByNodeID: [String: SpanData] = [:]

        for span in spans {
            let node = FlowGraphNode(span: span)
            newNodes.append(node)
            newNodesByID[node.id] = node
            newSpansByNodeID[node.id] = span
        }

        // Build parent-child relationships
        let spanIdSet = Set(newNodes.map(\.id))
        for node in newNodes {
            if let parentId = node.parentSpanId, spanIdSet.contains(parentId) {
                newNodesByID[parentId]?.childIDs.append(node.id)
            }
        }

        // Find roots and assign depths
        let rootNodes = newNodes.filter { node in
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

        for root in rootNodes {
            assignDepth(root.id, depth: 0)
        }

        let rootIDs = rootNodes.map(\.id)

        // Layout
        TraceTreeLayoutEngine.layout(
            nodes: newNodes,
            nodesByID: newNodesByID,
            roots: rootIDs,
            expandedIDs: expandedNodeIDs
        )

        // Generate edges
        let newEdges = generateEdges(nodes: newNodes, nodesByID: newNodesByID)

        self.nodes = newNodes
        self.nodesByID = newNodesByID
        self.spansByNodeID = newSpansByNodeID
        self.roots = rootIDs
        self.edges = newEdges

        // Initialize edge progress
        for edge in newEdges {
            if edgeProgress[edge.id] == nil {
                edgeProgress[edge.id] = 0.0
            }
        }
    }

    /// Incremental update: diff new spans against existing, animate new nodes in.
    private func incrementalUpdate() {
        let allSpans = trace.spans

        var changed = false
        var newNodeIDs: Set<String> = []

        for span in allSpans {
            let spanID = span.spanId.hexString

            // Update existing nodes (status changes: running → completed)
            if let existingNode = nodesByID[spanID] {
                if span.status.isError && existingNode.status != .error {
                    existingNode.status = .error
                    changed = true
                } else if span.endTime > span.startTime && existingNode.status == .running {
                    existingNode.status = .completed
                    changed = true
                }
                continue
            }

            // New span — add incrementally
            let node = FlowGraphNode(span: span)
            nodes.append(node)
            nodesByID[node.id] = node
            spansByNodeID[node.id] = span
            newNodeIDs.insert(node.id)

            // Wire parent-child
            if let parentId = node.parentSpanId, let parent = nodesByID[parentId] {
                parent.childIDs.append(node.id)
                node.depth = parent.depth + 1
                parent.childIDs.sort { a, b in
                    let na = nodesByID[a]?.startTime ?? .distantPast
                    let nb = nodesByID[b]?.startTime ?? .distantPast
                    return na < nb
                }
            } else {
                // New root
                if !roots.contains(node.id) {
                    roots.append(node.id)
                }
            }

            changed = true
        }

        guard changed else { return }

        // Re-layout with animation (siblings slide apart for new nodes)
        TraceTreeLayoutEngine.layout(
            nodes: nodes,
            nodesByID: nodesByID,
            roots: roots,
            expandedIDs: expandedNodeIDs
        )

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            edges = generateEdges(nodes: nodes, nodesByID: nodesByID)
            layoutGeneration += 1
        }

        // Animate new edges and nodes
        for edge in edges where newNodeIDs.contains(edge.toNodeID) {
            edgeProgress[edge.id] = 0.0
            // Draw edge progressively
            withAnimation(.easeOut(duration: 0.4)) {
                edgeProgress[edge.id] = 1.0
            }
            // Node materializes at 60% of edge draw (delayed by 0.24s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    visibleNodeIDs.formUnion(newNodeIDs)
                }
            }
        }

        // If no edges to animate (e.g., new root), just show immediately
        let newRoots = newNodeIDs.filter { roots.contains($0) }
        if !newRoots.isEmpty {
            DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.entrance) {
                visibleNodeIDs.formUnion(newRoots)
            }
        }
    }

    private func relayout() {
        TraceTreeLayoutEngine.layout(
            nodes: nodes,
            nodesByID: nodesByID,
            roots: roots,
            expandedIDs: expandedNodeIDs
        )

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            edges = generateEdges(nodes: nodes, nodesByID: nodesByID)
            layoutGeneration += 1  // Force Canvas + node positions to re-read
        }
    }

    private func generateEdges(nodes: [FlowGraphNode], nodesByID: [String: FlowGraphNode]) -> [TraceTreeEdge] {
        var newEdges: [TraceTreeEdge] = []
        for node in nodes {
            for childID in node.childIDs {
                guard let child = nodesByID[childID] else { continue }
                var edge = TraceTreeEdge(from: node.id, to: childID)
                // Parent right-center -> child left-center
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
        return newEdges
    }

    // MARK: - Staggered Entrance

    private func staggerNodeEntrance() async {
        visibleNodeIDs.removeAll()
        entranceComplete = false
        edgeProgress = [:]

        let maxDepth = nodes.map(\.depth).max() ?? 0
        for depth in 0...maxDepth {
            let nodesAtDepth = nodes.filter { $0.depth == depth }.map(\.id)

            // Make nodes visible
            DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.entrance) {
                visibleNodeIDs.formUnion(nodesAtDepth)
            }

            // Animate edges leading TO this depth level
            let edgesToThisDepth = edges.filter { edge in
                guard let child = nodesByID[edge.toNodeID] else { return false }
                return child.depth == depth
            }
            for edge in edgesToThisDepth {
                withAnimation(.easeOut(duration: 0.4)) {
                    edgeProgress[edge.id] = 1.0
                }
            }

            try? await Task.sleep(for: .milliseconds(60))
        }
        entranceComplete = true
    }

    // MARK: - Content Size

    private var contentSize: CGSize {
        guard !nodes.isEmpty else { return CGSize(width: 400, height: 300) }
        let maxX = nodes.map { $0.position.x + $0.size.width }.max() ?? 400
        let maxY = nodes.map { $0.position.y + $0.size.height }.max() ?? 300
        return CGSize(width: maxX + 80, height: maxY + 80)
    }

    // MARK: - Scrollable Content

    private var scrollableContent: some View {
        ScrollViewReader { scrollProxy in
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    // Layer 1: Canvas — draws all edges as horizontal bezier S-curves
                    Canvas { context, size in
                        let scale = zoomScale
                        for edge in edges {
                            let progress = edgeProgress[edge.id] ?? (entranceComplete ? 1.0 : 0.0)
                            guard progress > 0 else { continue }

                            // Scale edge points to match the zoomed Canvas frame
                            let scaledFrom = CGPoint(x: edge.fromPoint.x * scale, y: edge.fromPoint.y * scale)
                            let scaledTo = CGPoint(x: edge.toPoint.x * scale, y: edge.toPoint.y * scale)

                            let scaledMidX = (scaledFrom.x + scaledTo.x) / 2
                            let fullPath = Path { p in
                                p.move(to: scaledFrom)
                                p.addCurve(
                                    to: scaledTo,
                                    control1: CGPoint(x: scaledMidX, y: scaledFrom.y),
                                    control2: CGPoint(x: scaledMidX, y: scaledTo.y)
                                )
                            }
                            let path = progress >= 1.0 ? fullPath : fullPath.trimmedPath(from: 0, to: progress)

                            let isHighlighted = hoveredNodeID == edge.fromNodeID || hoveredNodeID == edge.toNodeID
                            let strokeColor = isHighlighted ? edge.hoverColor : edge.color

                            // Critical path glow
                            if edge.isCriticalPath {
                                context.stroke(
                                    path,
                                    with: .color(strokeColor.opacity(0.2)),
                                    lineWidth: edge.lineWidth * 3
                                )
                            }

                            if edge.isActive {
                                // Animated dashed stroke for running spans
                                context.stroke(
                                    path,
                                    with: .color(strokeColor),
                                    style: StrokeStyle(lineWidth: edge.lineWidth, dash: [6, 4], dashPhase: dashPhase)
                                )
                            } else {
                                context.stroke(
                                    path,
                                    with: .color(strokeColor),
                                    lineWidth: edge.lineWidth
                                )
                            }

                            // Arrow head (only when fully drawn)
                            if progress >= 0.95 {
                                let arrowSize: CGFloat = 6
                                let angle = atan2(scaledTo.y - scaledFrom.y, scaledTo.x - scaledFrom.x)
                                let arrowPath = Path { p in
                                    p.move(to: scaledTo)
                                    p.addLine(to: CGPoint(
                                        x: scaledTo.x - arrowSize * cos(angle - .pi / 6),
                                        y: scaledTo.y - arrowSize * sin(angle - .pi / 6)
                                    ))
                                    p.move(to: scaledTo)
                                    p.addLine(to: CGPoint(
                                        x: scaledTo.x - arrowSize * cos(angle + .pi / 6),
                                        y: scaledTo.y - arrowSize * sin(angle + .pi / 6)
                                    ))
                                }
                                context.stroke(
                                    arrowPath,
                                    with: .color(strokeColor),
                                    lineWidth: edge.lineWidth
                                )
                            }

                            // Token count label at midpoint (zoomed in)
                            if scale > 1.0, let tokenCount = edge.tokenCount, progress >= 1.0 {
                                let label = Text("\(tokenCount) tok")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(DashboardTheme.Colors.textSecondary)
                                let resolved = context.resolve(label)
                                let labelSize = resolved.measure(in: size)
                                let mid = CGPoint(
                                    x: (scaledFrom.x + scaledTo.x) / 2,
                                    y: (scaledFrom.y + scaledTo.y) / 2
                                )
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
                                context.draw(resolved, at: mid)
                            }
                        }
                    }
                    .frame(
                        width: contentSize.width * zoomScale,
                        height: contentSize.height * zoomScale
                    )

                    // Layer 2: SwiftUI overlay — positioned TraceTreeNodeView cards
                    // layoutGeneration dependency ensures positions update after relayout
                    let _ = layoutGeneration
                    ForEach(nodes) { node in
                        if let span = spansByNodeID[node.id] {
                            TraceTreeNodeView(
                                node: node,
                                span: span,
                                isSelected: selectedNodeID == node.id,
                                isExpanded: expandedNodeIDs.contains(node.id),
                                onTap: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                        if expandedNodeIDs.contains(node.id) {
                                            expandedNodeIDs.remove(node.id)
                                        } else {
                                            expandedNodeIDs.insert(node.id)
                                        }
                                        selectedNodeID = node.id
                                    }
                                    onSelectSpan?(node.spanId)
                                }
                            )
                            .id(node.id)
                            .position(
                                x: (node.position.x + node.size.width / 2) * zoomScale,
                                y: (node.position.y + node.size.height / 2) * zoomScale
                            )
                            .scaleEffect(zoomScale)
                            .opacity(visibleNodeIDs.contains(node.id) || entranceComplete ? 1 : 0)
                            .scaleEffect(visibleNodeIDs.contains(node.id) || entranceComplete ? 1 : 0.85)
                            .offset(x: visibleNodeIDs.contains(node.id) || entranceComplete ? 0 : -12)
                            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: visibleNodeIDs.contains(node.id))
                            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: expandedNodeIDs)
                            .onHover { hovering in
                                hoveredNodeID = hovering ? node.id : nil
                            }
                        }
                    }
                }
                .frame(
                    width: contentSize.width * zoomScale,
                    height: contentSize.height * zoomScale
                )
            }
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        let newScale = zoomScale * value.magnification
                        zoomScale = min(max(newScale, minZoom), maxZoom)
                    }
            )
            .onAppear {
                // Continuous dash animation for running spans
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    dashPhase = 10
                }
            }
        }
    }

    // MARK: - Jump to Latest Button

    private var jumpToLatestButton: some View {
        Button {
            autoFollowEnabled = true
            userHasScrolled = false
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.right.to.line")
                    .font(.system(size: 10, weight: .medium))
                Text("Latest")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(DashboardTheme.Colors.textSecondary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DashboardTheme.Spacing.md)
        .padding(.vertical, DashboardTheme.Spacing.sm + 2)
        .background(DashboardTheme.Colors.windowBackground)
        .clipShape(RoundedRectangle(cornerRadius: DashboardTheme.Spacing.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTheme.Spacing.cornerRadius)
                .strokeBorder(DashboardTheme.Colors.borderDefault, lineWidth: 1)
        )
        .shadow(color: DashboardTheme.Shadows.md.color, radius: DashboardTheme.Shadows.md.radius, y: DashboardTheme.Shadows.md.y)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    // MARK: - Zoom Controls

    private var zoomControls: some View {
        HStack(spacing: DashboardTheme.Spacing.sm) {
            Button {
                let content = contentSize
                guard content.width > 0, content.height > 0,
                      viewportSize.width > 0, viewportSize.height > 0 else { return }
                let scale = min(viewportSize.width / content.width, viewportSize.height / content.height)
                DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                    zoomScale = min(max(scale, minZoom), maxZoom)
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DashboardTheme.Colors.textSecondary)
            }
            .buttonStyle(.plain)

            Divider().frame(height: 14)

            Button {
                DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                    zoomScale = max(zoomScale - 0.25, minZoom)
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DashboardTheme.Colors.textSecondary)
            }
            .buttonStyle(.plain)

            Text("\(Int(zoomScale * 100))%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(DashboardTheme.Colors.textTertiary)
                .frame(width: 36)

            Button {
                DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                    zoomScale = min(zoomScale + 0.25, maxZoom)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DashboardTheme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DashboardTheme.Spacing.md)
        .padding(.vertical, DashboardTheme.Spacing.sm + 2)
        .background(DashboardTheme.Colors.windowBackground)
        .clipShape(RoundedRectangle(cornerRadius: DashboardTheme.Spacing.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTheme.Spacing.cornerRadius)
                .strokeBorder(DashboardTheme.Colors.borderDefault, lineWidth: 1)
        )
        .shadow(color: DashboardTheme.Shadows.md.color, radius: DashboardTheme.Shadows.md.radius, y: DashboardTheme.Shadows.md.y)
    }
}

// MARK: - Preference Key

private struct TreeViewportSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
