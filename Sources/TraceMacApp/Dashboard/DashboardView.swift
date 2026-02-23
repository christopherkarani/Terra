import Foundation
import SwiftUI
import TerraTraceKit

/// View mode for the content column.
enum TraceViewMode: String, CaseIterable {
    case events = "Events"
    case traceTree = "Tree"
    case timeline = "Timeline"

    var icon: String {
        switch self {
        case .events:    return "list.bullet.rectangle.portrait"
        case .traceTree: return "list.bullet.indent"
        case .timeline:  return "chart.bar.xaxis"
        }
    }
}

/// Sort order for the trace list.
enum TraceSortOrder: String, CaseIterable {
    case newestFirst = "Newest First"
    case oldestFirst = "Oldest First"
    case durationDesc = "Longest First"
    case durationAsc = "Shortest First"
}

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var sidebarWidth: CGFloat = 220

    var body: some View {
        @Bindable var appState = appState

        GeometryReader { geo in
            HStack(spacing: 0) {
                // Left sidebar: runtime groups
                if !appState.sidebarCollapsed {
                    RuntimeSidebarView()
                        .frame(width: sidebarWidth)
                    Divider()
                }

                // Main content: center flow graph + bottom span stream
                VStack(spacing: 0) {
                    FlowGraphContentArea()

                    ResizableDividerHandle(
                        height: $appState.bottomPanelHeight,
                        minHeight: 150,
                        maxHeight: min(400, geo.size.height * 0.6)
                    )

                    SpanEventStreamPanel()
                        .frame(height: appState.bottomPanelHeight)
                }
            }
        }
        .overlay {
            LoadingOverlayView(
                message: "Loading traces\u{2026}",
                isVisible: appState.isLoading
            )
        }
        .overlay(alignment: .top) {
            if let msg = appState.errorMessage {
                errorBanner(msg)
            }
        }
        .onKeyPress(.escape) {
            guard appState.errorMessage != nil else { return .ignored }
            DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                appState.errorMessage = nil
            }
            return .handled
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                        appState.sidebarCollapsed.toggle()
                    }
                } label: {
                    Label(
                        appState.sidebarCollapsed ? "Show Sidebar" : "Hide Sidebar",
                        systemImage: appState.sidebarCollapsed ? "sidebar.leading" : "sidebar.left"
                    )
                }
                .help("Toggle sidebar")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.setupOpenClawTracing()
                } label: {
                    Label("Quick Setup OpenClaw", systemImage: "bolt.badge.clock")
                }
                .disabled(appState.openClawPluginStatus == .installing)
                .help("Install diagnostics-otel, connect OpenClaw diagnostics, and start monitoring traces")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                        appState.isLiveMode.toggle()
                    }
                } label: {
                    Label(
                        appState.isLiveMode ? "Live Mode On" : "Live Mode Off",
                        systemImage: appState.isLiveMode ? "livephoto.play" : "livephoto"
                    )
                    .foregroundStyle(appState.isLiveMode ? DashboardTheme.Colors.accentSuccess : DashboardTheme.Colors.textSecondary)
                }
                .help("Toggle live mode \u{2014} auto-follow newest traces")
            }

            ToolbarItem(placement: .secondaryAction) {
                Button {
                    appState.installOpenClawDiagnosticsPlugin()
                } label: {
                    Label("Install OpenClaw Plugin", systemImage: "square.and.arrow.down")
                }
                .disabled(appState.openClawPluginStatus == .installing)
                .help("Install or repair the diagnostics-otel plugin")
            }

            ToolbarItem(placement: .secondaryAction) {
                Button {
                    appState.toggleOpenClawGatewayCapture()
                } label: {
                    Label(
                        appState.isOpenClawGatewayCaptureEnabled ? "Disable OpenClaw Gateway" : "Enable OpenClaw Gateway",
                        systemImage: appState.isOpenClawGatewayCaptureEnabled ? "bolt.slash" : "bolt"
                    )
                }
                .help("Toggle live OpenClaw gateway capture")
            }

            ToolbarItem(placement: .secondaryAction) {
                Button {
                    appState.toggleOpenClawTransparentMode()
                } label: {
                    Label(
                        appState.isOpenClawTransparentModeEnabled ? "Disable Transparent Mode" : "Enable Transparent Mode",
                        systemImage: appState.isOpenClawTransparentModeEnabled ? "eye.slash" : "eye"
                    )
                }
                .disabled(appState.isApplyingTransparentMode)
                .help("Toggle transparent mode intent for OpenClaw traffic redirection")
            }
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: DashboardTheme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
            Text(msg)
                .font(.system(size: 12, weight: .medium))
            Button {
                DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                    appState.errorMessage = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, DashboardTheme.Spacing.lg)
        .padding(.vertical, DashboardTheme.Spacing.md)
        .background(DashboardTheme.Colors.accentError.opacity(0.9))
        .foregroundStyle(.white)
        .clipShape(.rect(cornerRadius: DashboardTheme.Spacing.cornerRadius))
        .padding(.top, DashboardTheme.Spacing.md)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onTapGesture {
            DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                appState.errorMessage = nil
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(5))
            DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                appState.errorMessage = nil
            }
        }
    }
}

// MARK: - Flow Graph Content Area (center)

struct FlowGraphContentArea: View {
    @Environment(AppState.self) private var appState
    @Namespace private var modeNamespace
    @State private var livePulse = false
    @State private var eventListViewModel = TraceEventListViewModel()

    var body: some View {
        @Bindable var appState = appState

        if let trace = appState.selectedTrace {
            VStack(spacing: 0) {
                // KPI Strip
                KPIStripView()
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                // Metrics chart (collapsed by default, zero-height if no data)
                MetricsChartView(trace: trace)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                // View mode toggle + live indicator
                HStack {
                    // View mode toggle
                    HStack(spacing: 0) {
                        ForEach(TraceViewMode.allCases, id: \.self) { mode in
                            Button {
                                DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                                    appState.traceViewMode = mode
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: mode.icon)
                                        .font(.system(size: 10))
                                    Text(mode.rawValue)
                                        .font(.system(size: 11, weight: appState.traceViewMode == mode ? .semibold : .regular))
                                }
                                .foregroundStyle(appState.traceViewMode == mode ? DashboardTheme.Colors.textPrimary : DashboardTheme.Colors.textTertiary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background {
                                    if appState.traceViewMode == mode {
                                        DashboardTheme.Colors.surfaceActive
                                            .clipShape(.rect(cornerRadius: DashboardTheme.Spacing.cornerRadiusSmall))
                                            .matchedGeometryEffect(id: "modeIndicator", in: modeNamespace)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(DashboardTheme.Colors.surfaceRaised)
                    .clipShape(.rect(cornerRadius: DashboardTheme.Spacing.cornerRadius))

                    Spacer()

                    // Live indicator with pulsing dot
                    if appState.isLiveMode {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(DashboardTheme.Colors.accentSuccess)
                                .frame(width: 6, height: 6)
                                .scaleEffect(livePulse ? 1.3 : 1.0)
                                .opacity(livePulse ? 0.7 : 1.0)
                                .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.pulse), value: livePulse)
                                .onAppear { livePulse = true }
                                .onDisappear { livePulse = false }

                            Text("LIVE")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(DashboardTheme.Colors.accentSuccess)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(DashboardTheme.Colors.successBackground)
                        .clipShape(.capsule)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .accessibilityLabel("Live mode active")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

                Divider()

                // Content area — view mode switch
                switch appState.traceViewMode {
                case .events:
                    EventCategoryFilterBar(viewModel: eventListViewModel)
                    TraceEventListView(viewModel: eventListViewModel)

                case .traceTree:
                    AgentActionTreeView(
                        trace: trace,
                        onSelectSpan: { spanId in
                            let span = trace.spans.first { $0.spanId.hexString == spanId }
                            appState.selectSpan(span)
                            appState.expandedStreamSpanId = spanId
                        }
                    )

                case .timeline:
                    if let viewModel = appState.timelineViewModel {
                        TimelineRulerView(trace: trace, zoomScale: appState.timelineZoomScale)

                        TraceTimelineCanvasView(
                            viewModel: viewModel,
                            selectedSpanId: appState.selectedSpan?.spanId,
                            onSelectSpan: { span in
                                appState.selectSpan(span)
                                appState.expandedStreamSpanId = span.spanId.hexString
                            },
                            maxEventMarkers: appState.timelineMaxEventMarkers,
                            zoomScale: $appState.timelineZoomScale
                        )
                    }
                }
            }
            .background(DashboardTheme.Colors.windowBackground)
            .onChange(of: trace.id) {
                eventListViewModel.update(trace: trace)
            }
            .onAppear {
                eventListViewModel.update(trace: trace)
            }
            .onKeyPress(characters: .init(charactersIn: "1")) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                    appState.traceViewMode = .events
                }
                return .handled
            }
            .onKeyPress(characters: .init(charactersIn: "2")) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                    appState.traceViewMode = .traceTree
                }
                return .handled
            }
            .onKeyPress(characters: .init(charactersIn: "3")) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                    appState.traceViewMode = .timeline
                }
                return .handled
            }
        } else {
            AggregatedDashboardView()
        }
    }
}
