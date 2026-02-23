import SwiftUI
import TerraTraceKit
import OpenTelemetrySdk
import OpenTelemetryApi

/// Tabbed detail view for the currently selected span.
/// Three consolidated tabs: Overview, Events, Raw.
struct SpanDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: DetailTab = .overview
    @State private var viewModel = SpanDetailViewModel()
    @Namespace private var tabNamespace

    var body: some View {
        Group {
            if let span = appState.selectedSpan {
                VStack(alignment: .leading, spacing: 0) {
                    SpanDetailHeaderView(span: span)
                        .padding(.horizontal, DashboardTheme.Spacing.cardPadding)
                        .padding(.top, DashboardTheme.Spacing.cardPadding)
                        .padding(.bottom, DashboardTheme.Spacing.md)

                    tabBar
                        .padding(.horizontal, DashboardTheme.Spacing.cardPadding)

                    Divider()

                    tabContent
                        .padding(DashboardTheme.Spacing.cardPadding)
                }
                .onChange(of: span.spanId) {
                    viewModel.select(span: span)
                }
                .onAppear {
                    viewModel.select(span: span)
                }
            } else {
                noSpanSelected
            }
        }
    }
}

// MARK: - Detail Tab

extension SpanDetailView {
    enum DetailTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case events = "Events"
        case raw = "Raw"

        var id: String { rawValue }
    }
}

// MARK: - Subviews

private struct NoSpanSelectedView: View {
    var body: some View {
        ContentUnavailableView(
            "No Span Selected",
            systemImage: "sidebar.right",
            description: Text("Select a span to view its details")
        )
    }
}

private extension SpanDetailView {
    var noSpanSelected: some View {
        NoSpanSelectedView()
    }

    /// Horizontal tab bar with underline indicator and count badges.
    var tabBar: some View {
        HStack(spacing: DashboardTheme.Spacing.xl) {
            ForEach(DetailTab.allCases) { tab in
                tabButton(tab)
            }
        }
    }

    func tabButton(_ tab: DetailTab) -> some View {
        Button {
            DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: DashboardTheme.Spacing.sm) {
                HStack(spacing: DashboardTheme.Spacing.xs) {
                    Text(tab.rawValue)
                        .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .medium))
                        .foregroundStyle(selectedTab == tab ? DashboardTheme.Colors.textPrimary : DashboardTheme.Colors.textTertiary)

                    if let count = tabCount(tab), count > 0 {
                        Text("\(count)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(DashboardTheme.Colors.textTertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(DashboardTheme.Colors.surfaceRaised)
                            .clipShape(.rect(cornerRadius: DashboardTheme.Spacing.cornerRadiusSmall))
                    }
                }

                // Underline indicator — sliding via matchedGeometryEffect
                if selectedTab == tab {
                    Rectangle()
                        .fill(DashboardTheme.Colors.textPrimary)
                        .frame(height: 2)
                        .matchedGeometryEffect(id: "tabIndicator", in: tabNamespace)
                } else {
                    Rectangle()
                        .fill(.clear)
                        .frame(height: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
        .accessibilityHint("Show \(tab.rawValue) tab")
    }

    func tabCount(_ tab: DetailTab) -> Int? {
        switch tab {
        case .overview: return nil
        case .events: return viewModel.eventItems.count
        case .raw: return viewModel.attributeItems.count
        }
    }

    @ViewBuilder
    var tabContent: some View {
        Group {
            switch selectedTab {
            case .overview:
                overviewContent

            case .events:
                eventsContent

            case .raw:
                rawContent
            }
        }
        .transition(.opacity)
        .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.standard), value: selectedTab)
        .id(selectedTab)
    }

    // MARK: - Overview Tab

    var overviewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
                if let span = appState.selectedSpan {
                    // Key attributes grid
                    overviewKeyAttributes(span: span)
                }
            }
        }
    }

    func overviewKeyAttributes(span: SpanData) -> some View {
        let attrs = span.attributes
        let duration = span.endTime.timeIntervalSince(span.startTime)

        return VStack(alignment: .leading, spacing: DashboardTheme.Spacing.md) {
            // Status + Duration row
            HStack(spacing: DashboardTheme.Spacing.lg) {
                overviewField(label: "Status", value: span.status.isError ? "Error" : (span.endTime > span.startTime ? "OK" : "Running"), color: span.status.isError ? DashboardTheme.Colors.accentError : DashboardTheme.Colors.accentSuccess)

                overviewField(label: "Duration", value: TraceFormatter.duration(duration))
            }

            Divider()

            // Model info (if present)
            if let model = attrs["gen_ai.request.model"]?.description ?? attrs["llm.model"]?.description {
                overviewField(label: "Model", value: model)
            }

            // Token info
            let inputTokens = attrs["gen_ai.usage.input_tokens"]?.description ?? attrs["llm.usage.prompt_tokens"]?.description
            let outputTokens = attrs["gen_ai.usage.completion_tokens"]?.description ?? attrs["llm.usage.completion_tokens"]?.description
            if inputTokens != nil || outputTokens != nil {
                HStack(spacing: DashboardTheme.Spacing.lg) {
                    if let input = inputTokens {
                        overviewField(label: "Input Tokens", value: input)
                    }
                    if let output = outputTokens {
                        overviewField(label: "Output Tokens", value: output)
                    }
                }
            }

            // Latency metrics
            if let ttft = attrs["gen_ai.server.time_to_first_token"]?.description {
                overviewField(label: "Time to First Token", value: "\(ttft)ms")
            }

            if let tps = attrs["gen_ai.server.tokens_per_second"]?.description {
                overviewField(label: "Tokens/sec", value: tps)
            }

            // Span kind
            overviewField(label: "Kind", value: kindLabel(span.kind))

            // Timestamp
            overviewField(label: "Started", value: TraceFormatter.timestamp(span.startTime))
        }
    }

    func overviewField(label: String, value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DashboardTheme.Colors.textTertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(color ?? DashboardTheme.Colors.textPrimary)
                .lineLimit(1)
        }
    }

    func kindLabel(_ kind: OpenTelemetryApi.SpanKind) -> String {
        switch kind {
        case .internal: return "Internal"
        case .client: return "Client"
        case .server: return "Server"
        case .producer: return "Producer"
        case .consumer: return "Consumer"
        @unknown default: return "Unknown"
        }
    }

    // MARK: - Events Tab (merged with category filter chips)

    var eventsContent: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.md) {
            // Category filter chips
            let counts = viewModel.eventCategoryCounts
            let hasCategories = counts.values.contains(where: { $0 > 0 })
            if hasCategories {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(counts.sorted(by: { $0.key < $1.key }), id: \.key) { category, count in
                            if count > 0 {
                                HStack(spacing: 3) {
                                    Text(category)
                                        .font(.system(size: 9, weight: .medium))
                                    Text("\(count)")
                                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(DashboardTheme.Colors.surfaceRaised)
                                        .clipShape(.rect(cornerRadius: DashboardTheme.Spacing.cornerRadiusSmall))
                                }
                                .foregroundStyle(DashboardTheme.Colors.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(DashboardTheme.Colors.surfaceHover)
                                .clipShape(.capsule)
                            }
                        }
                    }
                }
            }

            // All events in chronological order
            SpanEventsTable(items: viewModel.eventItems, maxRows: appState.spanEventsRowLimit)
        }
    }

    // MARK: - Raw Tab (attributes + links)

    var rawContent: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
            SpanAttributesTable(items: viewModel.attributeItems)

            if !viewModel.linkItems.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: DashboardTheme.Spacing.sm) {
                    Text("Links")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DashboardTheme.Colors.textPrimary)
                    SpanLinksTable(items: viewModel.linkItems)
                }
            }
        }
    }
}

// MARK: - Header

/// Span name (14pt semibold) + status badge | clock icon + duration | kind badge | timestamp.
private struct SpanDetailHeaderView: View {
    let span: SpanData

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.sm) {
            HStack(spacing: DashboardTheme.Spacing.md) {
                Text(span.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DashboardTheme.Colors.textPrimary)
                    .lineLimit(1)

                if span.status.isError {
                    StatusBadge(kind: .error)
                }
            }

            HStack(spacing: DashboardTheme.Spacing.lg) {
                HStack(spacing: DashboardTheme.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(DashboardTheme.Colors.textTertiary)
                    Text(TraceFormatter.duration(
                        span.endTime.timeIntervalSince(span.startTime)
                    ))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DashboardTheme.Colors.textSecondary)
                }

                KindBadgeView(kind: span.kind)

                Text(TraceFormatter.timestamp(span.startTime))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DashboardTheme.Colors.textTertiary)
            }
        }
    }
}

/// Displays the span kind as a styled capsule badge.
private struct KindBadgeView: View {
    let kind: OpenTelemetryApi.SpanKind

    var body: some View {
        Text(label)
            .font(DashboardTheme.Fonts.badge)
            .foregroundStyle(DashboardTheme.Colors.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(DashboardTheme.Colors.surfaceRaised)
            .clipShape(.rect(cornerRadius: DashboardTheme.Spacing.cornerRadiusSmall))
    }

    private var label: String {
        switch kind {
        case .internal:
            "Internal"
        case .client:
            "Client"
        case .server:
            "Server"
        case .producer:
            "Producer"
        case .consumer:
            "Consumer"
        @unknown default:
            "Unknown"
        }
    }
}
