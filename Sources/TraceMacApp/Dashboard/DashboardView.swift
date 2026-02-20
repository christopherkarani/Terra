import Foundation
import SwiftUI
import TerraTraceKit

struct DashboardView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            TraceListView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } content: {
            DashboardContentColumn()
                .navigationSplitViewColumnWidth(min: 400, ideal: 600, max: .infinity)
        } detail: {
            DashboardDetailColumn()
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 400)
        }
        .overlay {
            LoadingOverlayView(
                message: "Loading traces\u{2026}",
                isVisible: appState.isLoading
            )
        }
        .overlay(alignment: .top) {
            if let msg = appState.errorMessage {
                Text(msg)
                    .padding(8)
                    .background(.red.opacity(0.85))
                    .foregroundStyle(.white)
                    .cornerRadius(6)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.setupOpenClawTracing()
                } label: {
                    Label("Quick Setup OpenClaw", systemImage: "bolt.badge.clock")
                }
                .disabled(appState.openClawPluginStatus == .installing)
                .help("Install diagnostics-otel, connect OpenClaw diagnostics, and start monitoring traces")
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
}

struct DashboardContentColumn: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        if let trace = appState.selectedTrace,
           let viewModel = appState.timelineViewModel {
            VStack(spacing: 0) {
                KPICardsView()
                    .padding(.horizontal)
                    .padding(.top)

                DashboardVolumeControlsView()
                    .padding(.horizontal)
                    .padding(.bottom, 10)

                Divider()

                TimelineRulerView(trace: trace, zoomScale: appState.timelineZoomScale)

                TraceTimelineCanvasView(
                    viewModel: viewModel,
                    selectedSpanId: appState.selectedSpan?.spanId,
                    onSelectSpan: { span in
                        appState.selectSpan(span)
                    },
                    maxEventMarkers: appState.timelineMaxEventMarkers,
                    zoomScale: $appState.timelineZoomScale
                )
            }
        } else {
            EmptyStateView(
                symbolName: "chart.bar.xaxis",
                title: "Select a trace",
                subtitle: "Choose a trace from the sidebar to view its timeline"
            )
        }
    }
}

private struct DashboardVolumeControlsView: View {
    @Environment(AppState.self) private var appState

    private var zoomRange: ClosedRange<CGFloat> {
        CGFloat(AppSettings.timelineZoomScaleRange.lowerBound)...CGFloat(AppSettings.timelineZoomScaleRange.upperBound)
    }

    var body: some View {
        @Bindable var appState = appState

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Volume Controls")
                    .font(DashboardTheme.sectionHeader)
                    .foregroundStyle(DashboardTheme.textPrimary)
                Spacer()
                Button("Reset Defaults") {
                    appState.tracePageSizeSetting = AppSettings.defaultTracePageSize
                    appState.timelineMaxEventMarkers = AppSettings.defaultTimelineMaxEventMarkers
                    appState.spanEventsRowLimit = AppSettings.defaultSpanEventsRowLimit
                    appState.timelineZoomScale = CGFloat(AppSettings.defaultTimelineZoomScale)
                }
                .controlSize(.small)
            }

            HStack(spacing: 12) {
                Stepper(value: $appState.tracePageSizeSetting, in: AppSettings.tracePageSizeRange, step: 25) {
                    Text("Trace page size: \(appState.tracePageSizeSetting)")
                        .font(DashboardTheme.detail)
                }

                Stepper(value: $appState.timelineMaxEventMarkers, in: AppSettings.timelineMaxEventMarkersRange, step: 100) {
                    Text("Timeline markers: \(appState.timelineMaxEventMarkers)")
                        .font(DashboardTheme.detail)
                }

                Stepper(value: $appState.spanEventsRowLimit, in: AppSettings.spanEventsRowLimitRange, step: 25) {
                    Text("Event rows: \(appState.spanEventsRowLimit)")
                        .font(DashboardTheme.detail)
                }
            }

            HStack(spacing: 10) {
                Text("Timeline zoom")
                    .font(DashboardTheme.detail)
                    .frame(width: 84, alignment: .leading)
                Slider(value: $appState.timelineZoomScale, in: zoomRange, step: 0.05)
                Text(String(format: "%.2fx", Double(appState.timelineZoomScale)))
                    .font(DashboardTheme.detail.monospacedDigit())
                    .frame(width: 58, alignment: .trailing)
                Button("Reset Zoom") {
                    appState.timelineZoomScale = CGFloat(AppSettings.defaultTimelineZoomScale)
                }
                .controlSize(.small)
            }

            Text("Controls are persisted and apply immediately to loading, timeline rendering, and event tables.")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(DashboardTheme.surfaceBackground)
        )
    }
}

struct DashboardDetailColumn: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.selectedTrace != nil {
            SpanInspectorView()
        } else {
            EmptyStateView(
                symbolName: "sidebar.right",
                title: "No span selected",
                subtitle: "Select a span from the timeline to inspect its details"
            )
        }
    }
}
