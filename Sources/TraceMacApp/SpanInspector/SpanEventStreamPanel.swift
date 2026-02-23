import SwiftUI
import TerraTraceKit
import OpenTelemetrySdk

/// Category filter for the span event stream panel.
enum SpanStreamCategory: String, CaseIterable {
    case inference = "INFERENCE"
    case tool = "TOOL"
    case agent = "AGENT"
    case embedding = "EMBED"
    case safety = "SAFETY"

    var accentColor: Color {
        switch self {
        case .inference: return DashboardTheme.Colors.nodeInference
        case .tool:      return DashboardTheme.Colors.nodeTool
        case .agent:     return DashboardTheme.Colors.nodeAgent
        case .embedding: return DashboardTheme.Colors.nodeEmbedding
        case .safety:    return DashboardTheme.Colors.nodeSafety
        }
    }

    func matches(_ kind: FlowNodeKind) -> Bool {
        switch (self, kind) {
        case (.inference, .inference): return true
        case (.tool, .tool):           return true
        case (.agent, .agent):         return true
        case (.embedding, .embedding): return true
        case (.safety, .safetyCheck):  return true
        default:                       return false
        }
    }
}

/// Bottom panel: filterable span event stream with category pills and inline expandable detail.
struct SpanEventStreamPanel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            if let trace = appState.selectedTrace {
                let spans = filteredSpans(trace: trace)

                // Category filter pills
                categoryPills(trace: trace)
                    .padding(.horizontal, DashboardTheme.Spacing.lg)
                    .padding(.vertical, DashboardTheme.Spacing.md)

                Divider()

                // Span list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(spans, id: \.spanId) { span in
                                let spanIdStr = span.spanId.hexString
                                let isExpanded = appState.expandedStreamSpanId == spanIdStr

                                SpanStreamRow(
                                    span: span,
                                    isExpanded: isExpanded,
                                    isSelected: appState.selectedSpan?.spanId == span.spanId,
                                    onTap: {
                                        DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                                            if isExpanded {
                                                appState.expandedStreamSpanId = nil
                                            } else {
                                                appState.expandedStreamSpanId = spanIdStr
                                                appState.selectSpan(span)
                                            }
                                        }
                                    }
                                )
                                .id(spanIdStr)

                                Divider()
                                    .padding(.horizontal, DashboardTheme.Spacing.lg)
                            }
                        }
                    }
                    .onChange(of: appState.expandedStreamSpanId) { _, newId in
                        if let newId {
                            withAnimation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.standard)) {
                                proxy.scrollTo(newId, anchor: .center)
                            }
                        }
                    }
                }
            } else {
                EmptyStateView(
                    symbolName: "list.bullet.rectangle",
                    title: "No trace selected",
                    subtitle: "Select a trace to view spans"
                )
            }
        }
        .background(DashboardTheme.Colors.windowBackground)
    }

    // MARK: - Category Pills

    private func categoryPills(trace: Trace) -> some View {
        let allSpans = trace.spans.sorted { $0.startTime < $1.startTime }
        let categoryCounts = SpanStreamCategory.allCases.map { category in
            (category, allSpans.filter { category.matches(FlowNodeKind.classify(span: $0)) }.count)
        }

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // ALL pill
                categoryPill(
                    label: "ALL",
                    count: allSpans.count,
                    isActive: appState.streamCategoryFilter == nil,
                    color: DashboardTheme.Colors.textSecondary,
                    onTap: {
                        DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                            @Bindable var appState = appState
                            appState.streamCategoryFilter = nil
                        }
                    }
                )

                ForEach(categoryCounts, id: \.0) { category, count in
                    if count > 0 {
                        categoryPill(
                            label: category.rawValue,
                            count: count,
                            isActive: appState.streamCategoryFilter == category,
                            color: category.accentColor,
                            onTap: {
                                DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                                    @Bindable var appState = appState
                                    appState.streamCategoryFilter = appState.streamCategoryFilter == category ? nil : category
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private func categoryPill(label: String, count: Int, isActive: Bool, color: Color, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                Text("(\(count))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(isActive ? .white : DashboardTheme.Colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isActive ? color : DashboardTheme.Colors.surfaceRaised)
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filtering

    private func filteredSpans(trace: Trace) -> [SpanData] {
        let sorted = trace.spans.sorted { $0.startTime < $1.startTime }
        guard let filter = appState.streamCategoryFilter else { return sorted }
        return sorted.filter { filter.matches(FlowNodeKind.classify(span: $0)) }
    }
}
