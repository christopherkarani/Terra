import SwiftUI
import TerraTraceKit
import OpenTelemetrySdk

// MARK: - AgentActionTreeView

/// Vertical agent action tree — polished SaaS-grade card-based layout with
/// icon badges, timing waterfall bars, inline detail dropdowns, minimap rail,
/// and keyboard navigation.
struct AgentActionTreeView: View {
    let trace: Trace
    var onSelectSpan: ((String) -> Void)?

    // MARK: - State

    @State private var nodes: [FlowGraphNode] = []
    @State private var nodesByID: [String: FlowGraphNode] = [:]
    @State private var spansByNodeID: [String: SpanData] = [:]
    @State private var roots: [String] = []
    @State private var expandedNodeIDs: Set<String> = []
    @State private var focusedNodeID: String?
    @State private var flatItems: [FlatTreeItem] = []
    @State private var scrollViewProxy: ScrollViewProxy?
    @State private var scrollOffset: CGFloat = 0

    @FocusState private var isTreeFocused: Bool

    private var traceDuration: TimeInterval {
        trace.duration > 0 ? trace.duration : 1
    }

    private var isSingleSpan: Bool { nodes.count == 1 }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(flatItems) { item in
                                nodeRow(for: item)
                            }
                        }
                        .padding(.vertical, DashboardTheme.Spacing.lg)
                        .padding(.horizontal, DashboardTheme.Spacing.lg)
                        .background(
                            GeometryReader { inner in
                                Color.clear.preference(
                                    key: ScrollOffsetKey.self,
                                    value: inner.frame(in: .named("treeScroll")).minY
                                )
                            }
                        )
                    }
                    .coordinateSpace(name: "treeScroll")
                    .onPreferenceChange(ScrollOffsetKey.self) { value in
                        scrollOffset = value
                    }
                    .onAppear { scrollViewProxy = proxy }
                }

                if flatItems.count >= 20 {
                    minimapRail
                        .transition(.opacity)
                }
            }

            if !isSingleSpan && nodes.count > 1 {
                treeToolbar
            }
        }
        .background(DashboardTheme.Colors.windowBackground)
        .focusable()
        .focused($isTreeFocused)
        .onKeyPress(.downArrow) { moveFocus(by: 1); return .handled }
        .onKeyPress(.upArrow) { moveFocus(by: -1); return .handled }
        .onKeyPress(.return) {
            guard let id = focusedNodeID else { return .ignored }
            toggleExpansion(id)
            return .handled
        }
        .onKeyPress(.escape) {
            guard let id = focusedNodeID else { return .ignored }
            if expandedNodeIDs.contains(id) {
                _ = withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    expandedNodeIDs.remove(id)
                }
            } else {
                focusedNodeID = nil
            }
            return .handled
        }
        .task(id: trace.id) { buildGraph() }
        .onChange(of: trace.spans.count) { oldCount, newCount in
            guard newCount != oldCount, newCount > 0 else { return }
            incrementalUpdate()
        }
    }

    // MARK: - Node Row (card + connector + detail)

    @ViewBuilder
    private func nodeRow(for item: FlatTreeItem) -> some View {
        let nodeID = item.nodeID
        if let node = nodesByID[nodeID], let span = spansByNodeID[nodeID] {
            let indent = CGFloat(item.clampedDepth) * 28
            let isExpanded = expandedNodeIDs.contains(nodeID)
            let isHTTP = span.attributes["http.method"]?.description != nil
                || span.attributes["http.route"]?.description != nil

            VStack(alignment: .leading, spacing: 0) {
                // L-shaped connector from parent
                if item.depth > 0 {
                    connectorView(depth: item.clampedDepth, isLast: item.isLastChild)
                }

                // --- Node card ---
                AgentTreeNodeRow(
                    node: node,
                    span: span,
                    traceDuration: traceDuration,
                    isExpanded: isExpanded,
                    isFocused: focusedNodeID == nodeID,
                    isSingleSpan: isSingleSpan,
                    breadcrumb: item.depth > 3 ? breadcrumb(for: nodeID) : nil,
                    onTap: {
                        toggleExpansion(nodeID)
                        onSelectSpan?(node.spanId)
                    }
                )
                .id(nodeID)
                .padding(.leading, indent)
                .contextMenu { nodeContextMenu(node: node) }

                // --- Expanded detail panel (visually attached to card) ---
                if isExpanded {
                    HStack(alignment: .top, spacing: 0) {
                        // Continuing accent stripe
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(nodeAccentColor(for: node.kind, isHTTP: isHTTP))
                            .frame(width: 4)

                        TraceTreeDetailSection(node: node, span: span)
                            .padding(.leading, 10)
                            .padding(.trailing, 8)
                            .padding(.vertical, 8)
                    }
                    .padding(.top, 2)
                    .padding(.leading, indent + 1)
                    .padding(.trailing, 4)
                    .padding(.bottom, 2)
                    .background(
                        DashboardTheme.Colors.surfaceRaised.opacity(0.6)
                            .clipShape(.rect(
                                topLeadingRadius: 0,
                                bottomLeadingRadius: DashboardTheme.Spacing.cornerRadius,
                                bottomTrailingRadius: DashboardTheme.Spacing.cornerRadius,
                                topTrailingRadius: 0
                            ))
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    // MARK: - Accent Color (shared)

    private func nodeAccentColor(for kind: FlowNodeKind, isHTTP: Bool = false) -> Color {
        switch kind {
        case .agent:      return DashboardTheme.Colors.nodeAgent
        case .inference:  return DashboardTheme.Colors.nodeInference
        case .tool:       return DashboardTheme.Colors.nodeTool
        case .stage:      return DashboardTheme.Colors.nodeStage
        case .embedding:  return DashboardTheme.Colors.nodeEmbedding
        case .safetyCheck: return DashboardTheme.Colors.nodeSafety
        case .generic:
            return isHTTP ? DashboardTheme.Colors.nodeInference : DashboardTheme.Colors.nodeStage
        }
    }

    // MARK: - Connector (L-shaped, stronger visibility)

    private func connectorView(depth: Int, isLast: Bool) -> some View {
        HStack(spacing: 0) {
            Spacer()
                .frame(width: CGFloat(max(depth - 1, 0)) * 28 + 12)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(DashboardTheme.Colors.borderStrong)
                    .frame(width: 1.5, height: isLast ? 12 : 20)

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(DashboardTheme.Colors.borderStrong)
                        .frame(width: 14, height: 1.5)
                    Spacer()
                }
            }
            .frame(width: 16, height: 20, alignment: isLast ? .top : .center)

            Spacer()
        }
        .frame(height: 20)
    }

    // MARK: - Breadcrumb (depth > 3)

    private func breadcrumb(for nodeID: String) -> String? {
        guard let node = nodesByID[nodeID] else { return nil }
        var path: [String] = []
        var current = node.parentSpanId
        while let parentID = current, let parent = nodesByID[parentID], path.count < 3 {
            path.insert(nodeLabel(for: parent), at: 0)
            current = parent.parentSpanId
        }
        return path.joined(separator: " \u{203a} ")
    }

    private func nodeLabel(for node: FlowGraphNode) -> String {
        if case .generic = node.kind {
            return node.spanName.isEmpty ? "span" : node.spanName
        }
        return node.kind.label
    }

    // MARK: - Minimap Rail

    private var minimapRail: some View {
        GeometryReader { geo in
            let totalHeight = geo.size.height
            let nodeCount = max(flatItems.count, 1)
            let dotSpacing = totalHeight / CGFloat(nodeCount)

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(DashboardTheme.Colors.surfaceRaised)
                    .frame(width: 24)

                ForEach(Array(flatItems.enumerated()), id: \.offset) { index, item in
                    if let node = nodesByID[item.nodeID] {
                        let isHTTP = spansByNodeID[item.nodeID].flatMap {
                            $0.attributes["http.method"]?.description
                        } != nil

                        Circle()
                            .fill(nodeAccentColor(for: node.kind, isHTTP: isHTTP))
                            .frame(width: 5, height: 5)
                            .opacity(focusedNodeID == item.nodeID ? 1.0 : 0.4)
                            .offset(x: 10, y: CGFloat(index) * dotSpacing + dotSpacing / 2)
                            .onTapGesture {
                                focusedNodeID = item.nodeID
                                scrollViewProxy?.scrollTo(item.nodeID, anchor: .center)
                            }
                    }
                }

                let viewportHeight = max(totalHeight * 0.25, 24)
                RoundedRectangle(cornerRadius: 3)
                    .fill(DashboardTheme.Colors.accentActive.opacity(0.12))
                    .frame(width: 20, height: viewportHeight)
                    .offset(x: 2, y: max(0, -scrollOffset * 0.1))
            }
        }
        .frame(width: 24)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(DashboardTheme.Colors.borderDefault)
                .frame(width: 1)
        }
    }

    // MARK: - Tree Toolbar

    private var treeToolbar: some View {
        HStack(spacing: DashboardTheme.Spacing.lg) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    expandedNodeIDs = Set(nodes.map(\.id))
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Expand All")
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    expandedNodeIDs.removeAll()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Collapse All")
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(nodes.count) spans")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(DashboardTheme.Colors.textTertiary)
        }
        .foregroundStyle(DashboardTheme.Colors.textSecondary)
        .padding(.horizontal, DashboardTheme.Spacing.lg)
        .padding(.vertical, 8)
        .background(DashboardTheme.Colors.sidebarBackground)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func nodeContextMenu(node: FlowGraphNode) -> some View {
        Button("Copy Span ID") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.spanId, forType: .string)
        }
        if let model = node.model {
            Button("Copy Model Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model, forType: .string)
            }
        }
        Button("Copy Duration") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(formatDuration(node.duration), forType: .string)
        }
        Divider()
        if !node.childIDs.isEmpty {
            Button(expandedNodeIDs.contains(node.id) ? "Collapse" : "Expand") {
                toggleExpansion(node.id)
            }
        }
    }

    // MARK: - Actions

    private func toggleExpansion(_ nodeID: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if expandedNodeIDs.contains(nodeID) {
                expandedNodeIDs.remove(nodeID)
            } else {
                expandedNodeIDs.insert(nodeID)
            }
        }
    }

    private func moveFocus(by delta: Int) {
        guard !flatItems.isEmpty else { return }
        let ids = flatItems.map(\.nodeID)
        if let current = focusedNodeID, let index = ids.firstIndex(of: current) {
            let newIndex = min(max(index + delta, 0), ids.count - 1)
            focusedNodeID = ids[newIndex]
        } else {
            focusedNodeID = delta > 0 ? ids.first : ids.last
        }
        if let id = focusedNodeID {
            scrollViewProxy?.scrollTo(id, anchor: .center)
        }
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

        let spanIdSet = Set(newNodes.map(\.id))
        for node in newNodes {
            if let parentId = node.parentSpanId, spanIdSet.contains(parentId) {
                newNodesByID[parentId]?.childIDs.append(node.id)
            }
        }

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

        var flat: [FlatTreeItem] = []
        func dfs(_ nodeID: String, depth: Int, isLastChild: Bool) {
            flat.append(FlatTreeItem(nodeID: nodeID, depth: depth, isLastChild: isLastChild))
            if let node = newNodesByID[nodeID] {
                for (index, childID) in node.childIDs.enumerated() {
                    dfs(childID, depth: depth + 1, isLastChild: index == node.childIDs.count - 1)
                }
            }
        }
        for (index, rootID) in rootIDs.enumerated() {
            dfs(rootID, depth: 0, isLastChild: index == rootIDs.count - 1)
        }

        self.nodes = newNodes
        self.nodesByID = newNodesByID
        self.spansByNodeID = newSpansByNodeID
        self.roots = rootIDs
        self.flatItems = flat

        // Auto-expand for small traces
        if newNodes.count <= 5 {
            expandedNodeIDs = Set(newNodes.map(\.id))
        }
    }

    private func incrementalUpdate() {
        let allSpans = trace.spans
        var changed = false

        for span in allSpans {
            let spanID = span.spanId.hexString

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

            let node = FlowGraphNode(span: span)
            nodes.append(node)
            nodesByID[node.id] = node
            spansByNodeID[node.id] = span

            if let parentId = node.parentSpanId, let parent = nodesByID[parentId] {
                parent.childIDs.append(node.id)
                node.depth = parent.depth + 1
                parent.childIDs.sort { a, b in
                    let na = nodesByID[a]?.startTime ?? .distantPast
                    let nb = nodesByID[b]?.startTime ?? .distantPast
                    return na < nb
                }
            } else if !roots.contains(node.id) {
                roots.append(node.id)
            }

            changed = true
        }

        guard changed else { return }

        var flat: [FlatTreeItem] = []
        func dfs(_ nodeID: String, depth: Int, isLastChild: Bool) {
            flat.append(FlatTreeItem(nodeID: nodeID, depth: depth, isLastChild: isLastChild))
            if let node = nodesByID[nodeID] {
                for (index, childID) in node.childIDs.enumerated() {
                    dfs(childID, depth: depth + 1, isLastChild: index == node.childIDs.count - 1)
                }
            }
        }
        for (index, rootID) in roots.enumerated() {
            dfs(rootID, depth: 0, isLastChild: index == roots.count - 1)
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            flatItems = flat
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else {
            return String(format: "%.1fs", duration)
        }
    }
}

// MARK: - FlatTreeItem

private struct FlatTreeItem: Identifiable {
    let nodeID: String
    let depth: Int
    let isLastChild: Bool

    var id: String { nodeID }
    var clampedDepth: Int { min(depth, 3) }
}

// MARK: - AgentTreeNodeRow (Card-Based Node)

private struct AgentTreeNodeRow: View {
    @ObservedObject var node: FlowGraphNode
    let span: SpanData
    let traceDuration: TimeInterval
    let isExpanded: Bool
    let isFocused: Bool
    let isSingleSpan: Bool
    let breadcrumb: String?
    var onTap: () -> Void = {}

    @State private var isHovered = false
    @State private var tapScale: CGFloat = 1.0
    @State private var isPulsing = false
    @State private var glowIntensity: CGFloat = 0
    @State private var statusDotScale: CGFloat = 1.0

    // MARK: - Derived Properties

    private var displayName: String {
        if case .generic = node.kind {
            return node.spanName.isEmpty ? "span" : node.spanName
        }
        return node.kind.label
    }

    private var httpMethod: String? {
        span.attributes["http.method"]?.description
    }

    private var httpStatusCode: Int? {
        if let str = span.attributes["http.status_code"]?.description { return Int(str) }
        return nil
    }

    private var modelName: String? { node.model }

    private var runtime: String? {
        span.attributes["terra.runtime"]?.description
    }

    private var isHTTPSpan: Bool {
        httpMethod != nil || span.attributes["http.route"]?.description != nil
    }

    private var accentColor: Color {
        switch node.kind {
        case .agent:      return DashboardTheme.Colors.nodeAgent
        case .inference:  return DashboardTheme.Colors.nodeInference
        case .tool:       return DashboardTheme.Colors.nodeTool
        case .stage:      return DashboardTheme.Colors.nodeStage
        case .embedding:  return DashboardTheme.Colors.nodeEmbedding
        case .safetyCheck: return DashboardTheme.Colors.nodeSafety
        case .generic:
            return isHTTPSpan ? DashboardTheme.Colors.nodeInference : DashboardTheme.Colors.nodeStage
        }
    }

    private var statusColor: Color {
        switch node.status {
        case .completed: return DashboardTheme.Colors.accentSuccess
        case .error:     return DashboardTheme.Colors.accentError
        case .running:   return DashboardTheme.Colors.accentActive
        case .pending:   return DashboardTheme.Colors.accentWarning
        }
    }

    private var durationColor: Color {
        if node.duration < 0.1 { return DashboardTheme.Colors.accentSuccess }
        if node.duration < 1.0 { return DashboardTheme.Colors.accentWarning }
        return DashboardTheme.Colors.accentError
    }

    private var formattedDuration: String {
        if node.duration < 1 {
            return String(format: "%.0fms", node.duration * 1000)
        } else {
            return String(format: "%.1fs", node.duration)
        }
    }

    /// Filled SF Symbol icon for each node kind.
    private var kindIcon: String {
        switch node.kind {
        case .agent:      return "person.crop.rectangle.fill"
        case .inference:  return "brain"
        case .tool:       return "wrench.and.screwdriver"
        case .stage:      return "gearshape.fill"
        case .embedding:  return "square.grid.3x3.fill"
        case .safetyCheck: return "checkmark.shield.fill"
        case .generic:
            if isHTTPSpan { return "arrow.up.arrow.down" }
            return "circle.grid.2x1.fill"
        }
    }

    // MARK: - Card styling

    private var cardBackground: Color {
        if isHovered { return DashboardTheme.Colors.surfaceHover }
        return DashboardTheme.Colors.surfaceRaised
    }

    private var cardBorderColor: Color {
        if isFocused { return DashboardTheme.Colors.accentActive }
        if isHovered { return DashboardTheme.Colors.borderStrong }
        return DashboardTheme.Colors.borderDefault
    }

    private var cardBorderWidth: CGFloat {
        isFocused ? 1.5 : 1
    }

    private var cardShadowColor: Color {
        if isHovered { return DashboardTheme.Shadows.md.color }
        return DashboardTheme.Shadows.sm.color
    }

    private var cardShadowRadius: CGFloat {
        if isHovered { return DashboardTheme.Shadows.md.radius }
        return DashboardTheme.Shadows.sm.radius
    }

    private var cardShadowY: CGFloat {
        if isHovered { return DashboardTheme.Shadows.md.y }
        return DashboardTheme.Shadows.sm.y
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Breadcrumb for deeply nested nodes
            if let breadcrumb {
                Text(breadcrumb)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(DashboardTheme.Colors.textQuaternary)
                    .padding(.leading, 40)
                    .padding(.bottom, 3)
            }

            // --- Card Surface ---
            VStack(alignment: .leading, spacing: 8) {
                // Row 1: icon badge + name + status dot + duration pill + chevron
                HStack(spacing: 10) {
                    iconBadge

                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.system(
                                size: node.kind.isAgent ? 13 : 12,
                                weight: node.kind.isAgent ? .semibold : .medium,
                                design: node.kind.isAgent ? .default : .monospaced
                            ))
                            .foregroundStyle(DashboardTheme.Colors.textPrimary)
                            .lineLimit(1)

                        // Inline metadata chips
                        metadataRow
                    }

                    Spacer(minLength: 0)

                    // Status dot
                    statusDot

                    // Duration pill
                    durationPill

                    // Expand chevron
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DashboardTheme.Colors.textTertiary)
                        .frame(width: 16, height: 16)
                }

                // Row 2: timing waterfall bar
                if !isSingleSpan {
                    waterfallBar
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(cardBackground)
            .clipShape(.rect(cornerRadius: DashboardTheme.Spacing.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DashboardTheme.Spacing.cornerRadius)
                    .strokeBorder(cardBorderColor, lineWidth: cardBorderWidth)
            )
            // Left accent stripe (4px, full height, snaps to left edge)
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(
                    topLeadingRadius: DashboardTheme.Spacing.cornerRadius,
                    bottomLeadingRadius: DashboardTheme.Spacing.cornerRadius,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0
                )
                .fill(accentColor)
                .frame(width: 4)
                .brightness(glowIntensity * 0.5)
                .shadow(color: accentColor.opacity(glowIntensity), radius: glowIntensity * 8)
            }
            // Agent crown stripe
            .overlay(alignment: .top) {
                if node.kind.isAgent {
                    UnevenRoundedRectangle(
                        topLeadingRadius: DashboardTheme.Spacing.cornerRadius,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: DashboardTheme.Spacing.cornerRadius
                    )
                    .fill(accentColor.opacity(0.6))
                    .frame(height: 3)
                }
            }
            .shadow(color: cardShadowColor, radius: cardShadowRadius, y: cardShadowY)
        }
        .scaleEffect(tapScale)
        .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.micro), value: isHovered)
        .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.micro), value: isFocused)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.7)) {
                tapScale = 0.98
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    tapScale = 1.0
                }
            }
            onTap()
        }
        .onChange(of: node.status) { oldValue, newValue in
            if oldValue == .running && newValue == .completed {
                triggerCompletionCascade()
            }
        }
    }

    // MARK: - Icon Badge

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(accentColor.opacity(0.1))
                .frame(width: 28, height: 28)

            Image(systemName: kindIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accentColor)
        }
    }

    // MARK: - Status Dot

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 7, height: 7)
            .scaleEffect(statusDotScale)
            .overlay {
                if node.status == .running {
                    Circle()
                        .stroke(statusColor.opacity(0.3), lineWidth: 2)
                        .frame(width: 12, height: 12)
                        .scaleEffect(isPulsing ? 1.8 : 1.0)
                        .opacity(isPulsing ? 0 : 0.7)
                        .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.pulse), value: isPulsing)
                        .onAppear { isPulsing = true }
                }
            }
    }

    // MARK: - Duration Pill

    private var durationPill: some View {
        Text(formattedDuration)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(durationColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(durationColor.opacity(0.1))
            .clipShape(Capsule())
    }

    // MARK: - Waterfall Bar

    private var waterfallBar: some View {
        GeometryReader { geo in
            let fraction = min(node.duration / traceDuration, 1.0)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(DashboardTheme.Colors.surfaceActive)
                    .frame(width: geo.size.width, height: 4)

                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor.opacity(0.3))
                    .frame(width: max(geo.size.width * fraction, 4), height: 4)
                    .animation(.easeInOut(duration: 0.3), value: node.status)
            }
        }
        .frame(height: 4)
        .padding(.leading, 38) // Align with name text (icon badge width + spacing)
    }

    // MARK: - Metadata Row

    @ViewBuilder
    private var metadataRow: some View {
        let hasTokens = node.inputTokens > 0 || node.outputTokens > 0
        let hasChips = modelName != nil || runtime != nil || httpStatusCode != nil || hasTokens

        if hasChips {
            HStack(spacing: 5) {
                if let model = modelName {
                    metadataChip(text: model, tint: DashboardTheme.Colors.nodeInference)
                }

                if let rt = runtime {
                    metadataChip(text: rt, tint: DashboardTheme.Colors.textTertiary)
                }

                if let code = httpStatusCode {
                    let tint: Color = code >= 400 ? DashboardTheme.Colors.accentError :
                        (code >= 300 ? DashboardTheme.Colors.accentWarning : DashboardTheme.Colors.accentSuccess)
                    metadataChip(text: "\(code)", tint: tint)
                }

                if hasTokens {
                    HStack(spacing: 3) {
                        Text("\(node.inputTokens)\u{2192}\(node.outputTokens) tok")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(DashboardTheme.Colors.textTertiary)

                        if let tps = node.tokensPerSecond {
                            Text("\u{00b7}")
                                .foregroundStyle(DashboardTheme.Colors.textQuaternary)
                            Text(String(format: "%.0f t/s", tps))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(DashboardTheme.Colors.textTertiary)
                        }
                    }
                }
            }
        }
    }

    private func metadataChip(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(tint.opacity(0.1))
            .clipShape(Capsule())
    }

    // MARK: - Helpers

    private func triggerCompletionCascade() {
        withAnimation(.easeIn(duration: 0.08)) {
            glowIntensity = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.2)) {
                glowIntensity = 0
            }
        }
        withAnimation(.spring(response: 0.1, dampingFraction: 0.5)) {
            statusDotScale = 1.4
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.7)) {
                statusDotScale = 1.0
            }
        }
        isPulsing = false
    }
}

// MARK: - Preference Key

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
