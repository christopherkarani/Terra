import SwiftUI
import TerraTraceKit
import OpenTelemetrySdk
import OpenTelemetryApi

/// Tabbed detail view for the currently selected span,
/// showing attributes, events, and links.
struct SpanDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: DetailTab = .attributes
    @State private var viewModel = SpanDetailViewModel()

    var body: some View {
        Group {
            if let span = appState.selectedSpan {
                VStack(alignment: .leading, spacing: DashboardTheme.sectionSpacing) {
                    SpanDetailHeaderView(span: span)
                    tabPicker
                    tabContent
                }
                .padding(DashboardTheme.contentPadding)
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
        case attributes = "Attributes"
        case events = "Events"
        case lifecycle = "Lifecycle"
        case policy = "Policy"
        case recommendations = "Recommendations"
        case anomalies = "Anomalies"
        case hardware = "Hardware"
        case links = "Links"

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

    var tabPicker: some View {
        Picker("Detail", selection: $selectedTab) {
            ForEach(DetailTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    var tabContent: some View {
        switch selectedTab {
        case .attributes:
            SpanAttributesTable(items: viewModel.attributeItems)
        case .events:
            SpanEventsTable(items: viewModel.eventItems, maxRows: appState.spanEventsRowLimit)
        case .lifecycle:
            SpanEventsTable(items: viewModel.lifecycleEventItems, maxRows: appState.spanEventsRowLimit)
        case .policy:
            SpanEventsTable(items: viewModel.policyEventItems, maxRows: appState.spanEventsRowLimit)
        case .recommendations:
            SpanEventsTable(items: viewModel.recommendationEventItems, maxRows: appState.spanEventsRowLimit)
        case .anomalies:
            SpanEventsTable(items: viewModel.anomalyEventItems, maxRows: appState.spanEventsRowLimit)
        case .hardware:
            SpanEventsTable(items: viewModel.hardwareEventItems, maxRows: appState.spanEventsRowLimit)
        case .links:
            SpanLinksTable(items: viewModel.linkItems)
        }
    }
}

// MARK: - Header

/// Displays summary information about the selected span:
/// name, kind, duration, and start time.
private struct SpanDetailHeaderView: View {
    let span: SpanData

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(span.name)
                    .font(DashboardTheme.sectionHeader)
                    .bold()

                KindBadgeView(kind: span.kind)

                if span.status.isError {
                    StatusBadge(isError: true)
                }
            }

            HStack(spacing: DashboardTheme.sectionSpacing) {
                Text(TraceFormatter.duration(
                    span.endTime.timeIntervalSince(span.startTime)
                ))
                .font(DashboardTheme.rowMeta)
                .foregroundStyle(.secondary)

                Text(TraceFormatter.timestamp(span.startTime))
                    .font(DashboardTheme.rowMeta)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Displays the span kind as a styled capsule badge.
private struct KindBadgeView: View {
    let kind: OpenTelemetryApi.SpanKind

    var body: some View {
        Text(label)
            .font(DashboardTheme.detail)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: .capsule)
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
