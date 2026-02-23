import SwiftUI
import TerraTraceKit
import OpenTelemetrySdk
import OpenTelemetryApi

/// Inline expandable detail for a span in the bottom panel.
/// Takes a SpanData directly (not from AppState), with Overview/Events/Raw tabs.
struct SpanInlineDetail: View {
    let span: SpanData
    @State private var selectedTab: DetailTab = .overview
    @State private var viewModel = SpanDetailViewModel()

    enum DetailTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case events = "Events"
        case raw = "Raw"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab bar
            HStack(spacing: DashboardTheme.Spacing.lg) {
                ForEach(DetailTab.allCases) { tab in
                    tabButton(tab)
                }
                Spacer()
            }
            .padding(.bottom, DashboardTheme.Spacing.md)

            Divider()
                .padding(.bottom, DashboardTheme.Spacing.md)

            // Tab content
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
            .frame(maxHeight: 200)
            .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.standard), value: selectedTab)
        }
        .onAppear {
            viewModel.select(span: span)
        }
        .onChange(of: span.spanId) {
            viewModel.select(span: span)
        }
    }

    // MARK: - Tab Button

    private func tabButton(_ tab: DetailTab) -> some View {
        Button {
            DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 2) {
                Text(tab.rawValue)
                    .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .medium))
                    .foregroundStyle(selectedTab == tab ? DashboardTheme.Colors.textPrimary : DashboardTheme.Colors.textTertiary)

                if let count = tabCount(tab), count > 0 {
                    Text("\(count)")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(DashboardTheme.Colors.textQuaternary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(selectedTab == tab ? DashboardTheme.Colors.surfaceActive : .clear)
            .clipShape(.rect(cornerRadius: DashboardTheme.Spacing.cornerRadiusSmall))
        }
        .buttonStyle(.plain)
    }

    private func tabCount(_ tab: DetailTab) -> Int? {
        switch tab {
        case .overview: return nil
        case .events: return viewModel.eventItems.count
        case .raw: return viewModel.attributeItems.count
        }
    }

    // MARK: - Overview

    private var overviewContent: some View {
        let duration = span.endTime.timeIntervalSince(span.startTime)
        let attrs = span.attributes

        return ScrollView {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.md) {
                HStack(spacing: DashboardTheme.Spacing.lg) {
                    statusFieldView(isError: span.status.isError)
                    fieldView(label: "Duration", value: TraceFormatter.duration(duration))
                }

                if let model = attrs["gen_ai.request.model"]?.description {
                    fieldView(label: "Model", value: model)
                }

                let inputTokens = attrs["gen_ai.usage.input_tokens"]?.description
                let outputTokens = attrs["gen_ai.usage.output_tokens"]?.description
                if inputTokens != nil || outputTokens != nil {
                    HStack(spacing: DashboardTheme.Spacing.lg) {
                        if let input = inputTokens {
                            fieldView(label: "Input", value: "\(input) tok")
                        }
                        if let output = outputTokens {
                            fieldView(label: "Output", value: "\(output) tok")
                        }
                    }
                }

                if let ttft = attrs["terra.latency.ttft_ms"]?.description {
                    fieldView(label: "TTFT", value: "\(ttft)ms")
                }
            }
        }
    }

    // MARK: - Events

    private var eventsContent: some View {
        ScrollView {
            SpanEventsTable(items: viewModel.eventItems, maxRows: 50)
        }
    }

    // MARK: - Raw

    private var rawContent: some View {
        ScrollView {
            SpanAttributesTable(items: viewModel.attributeItems)
        }
    }

    // MARK: - Field Helper

    private func statusFieldView(isError: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Status")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DashboardTheme.Colors.textQuaternary)
                .textCase(.uppercase)
            HStack(spacing: 4) {
                Circle()
                    .fill(isError ? DashboardTheme.Colors.accentError : DashboardTheme.Colors.accentSuccess)
                    .frame(width: 6, height: 6)
                Text(isError ? "Error" : "OK")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(isError ? DashboardTheme.Colors.accentError : DashboardTheme.Colors.accentSuccess)
                    .lineLimit(1)
            }
        }
    }

    private func fieldView(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DashboardTheme.Colors.textQuaternary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(DashboardTheme.Colors.textPrimary)
                .lineLimit(1)
        }
    }
}
