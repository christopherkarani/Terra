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
    @State private var zoomScale: CGFloat = 1.0

    var body: some View {
        if let trace = appState.selectedTrace,
           let viewModel = appState.timelineViewModel {
            VStack(spacing: 0) {
                KPICardsView()
                    .padding()

                Divider()

                TimelineRulerView(trace: trace, zoomScale: zoomScale)

                TraceTimelineCanvasView(
                    viewModel: viewModel,
                    selectedSpanId: appState.selectedSpan?.spanId,
                    onSelectSpan: { span in
                        appState.selectSpan(span)
                    },
                    zoomScale: $zoomScale
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
