import SwiftUI
import TerraTraceKit

struct TraceListView: View {
    @Environment(AppState.self) private var appState
    @State private var showOpenClawPopover = false

    private var isAnyFilterActive: Bool {
        appState.openClawSourceFilter != .all
            || appState.showOnlyErrors
    }

    @ViewBuilder
    private var traceCountLabel: some View {
        let query = appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            Text("\(appState.filteredTraces.count) of \(appState.traces.count)")
                .font(DashboardTheme.Fonts.rowMeta)
                .foregroundStyle(DashboardTheme.Colors.textSecondary)
        } else {
            Text("\(appState.filteredTraces.count)")
                .font(DashboardTheme.Fonts.rowMeta)
                .foregroundStyle(DashboardTheme.Colors.textSecondary)
        }
    }

    // MARK: - Default Header (all runtimes)

    @ViewBuilder
    private var defaultHeader: some View {
        @Bindable var appState = appState

        HStack {
            Text("TRACES")
                .font(DashboardTheme.Fonts.sectionHeader)
                .foregroundStyle(DashboardTheme.Colors.textTertiary)

            Spacer()

            traceCountLabel

            Menu {
                Picker("Source", selection: $appState.openClawSourceFilter) {
                    ForEach(OpenClawTraceSourceFilter.allCases, id: \.self) { filter in
                        Text(filter.title).tag(filter)
                    }
                }

                Picker("Sort", selection: $appState.traceSortOrder) {
                    ForEach(TraceSortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }

                Divider()

                Toggle("Errors Only", isOn: $appState.showOnlyErrors)

                Divider()

                Button {
                    showOpenClawPopover = true
                } label: {
                    Label("OpenClaw Setup", systemImage: "waveform.path.ecg")
                }

                Divider()

                Button(role: .destructive) {
                    appState.clearTraces()
                } label: {
                    Label("Clear Traces", systemImage: "trash")
                }
                .disabled(appState.traces.isEmpty)
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 12))
                    .foregroundStyle(DashboardTheme.Colors.textTertiary)
                    .overlay(alignment: .topTrailing) {
                        if isAnyFilterActive {
                            Circle()
                                .fill(DashboardTheme.Colors.accentActive)
                                .frame(width: 5, height: 5)
                                .offset(x: 2, y: -2)
                        }
                    }
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
            .accessibilityLabel(isAnyFilterActive ? "Filter menu, filters active" : "Filter menu")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Drill-In Header (filtered to a specific runtime)

    @ViewBuilder
    private var drillInHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                        appState.runtimeFilter = .all
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("All")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(DashboardTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Circle()
                    .fill(appState.runtimeFilter.accentColor)
                    .frame(width: 6, height: 6)
                Text(appState.runtimeFilter.title.uppercased())
                    .font(DashboardTheme.Fonts.sectionHeader)
                    .foregroundStyle(DashboardTheme.Colors.textTertiary)
            }

            runtimeSummaryStats
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Runtime Summary Stats

    @ViewBuilder
    private var runtimeSummaryStats: some View {
        let traces = appState.filteredTraces
        let metrics = DashboardViewModel.compute(from: traces)
        HStack(spacing: 0) {
            Text("avg TTFT \(TraceFormatter.duration(metrics.ttftP50))")
            Text(" \u{00b7} ").foregroundStyle(DashboardTheme.Colors.textQuaternary)
            Text(formattedErrorRate(metrics.errorRate))
                .foregroundStyle(metrics.errorRate > 0 ? DashboardTheme.Colors.accentError : DashboardTheme.Colors.textTertiary)
            Text(" \u{00b7} ").foregroundStyle(DashboardTheme.Colors.textQuaternary)
            Text("\(traces.count) traces")
        }
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(DashboardTheme.Colors.textTertiary)
    }

    private func formattedErrorRate(_ rate: Double) -> String {
        if rate <= 0 { return "0% err" }
        return TraceFormatter.errorRate(rate) + " err"
    }

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            // Header: conditional on drill-down state
            if appState.runtimeFilter == .all {
                defaultHeader
                    .transition(.asymmetric(
                        insertion: .push(from: .leading),
                        removal: .push(from: .trailing)
                    ))
                RuntimeSelectorBar()
            } else {
                drillInHeader
                    .transition(.asymmetric(
                        insertion: .push(from: .trailing),
                        removal: .push(from: .leading)
                    ))
            }

            Divider()

            // Trace list
            List(selection: Binding(
                get: { appState.selectedTrace?.id },
                set: { newID in
                    let trace = appState.filteredTraces.first { $0.id == newID }
                    appState.selectTrace(trace)
                }
            )) {
                ForEach(appState.filteredTraces, id: \.id) { trace in
                    TraceRowView(trace: trace, isLive: appState.isLiveMode && trace.isRecent)
                        .tag(trace.id)
                }
            }
            .listStyle(.plain)
            .searchable(text: $appState.searchQuery, prompt: "Search traces...")

            // Load more
            if appState.canLoadMoreTraces {
                Button {
                    appState.loadMoreTraces()
                } label: {
                    Text("Load more (\(appState.loadedTraceFileCount)/\(appState.totalTraceFileCount) files)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DashboardTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(GhostButtonStyle())
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }

            ConnectionStatusBar()
        }
        .background(DashboardTheme.Colors.sidebarBackground)
        .focusable()
        .onKeyPress(.escape) {
            guard appState.runtimeFilter != .all else { return .ignored }
            DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                appState.runtimeFilter = .all
            }
            return .handled
        }
        .popover(isPresented: $showOpenClawPopover) {
            OpenClawSetupCard()
                .frame(width: 320)
                .padding()
        }
    }
}

private struct OpenClawSetupCard: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("OpenClaw Tracing", systemImage: "waveform.path.ecg")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                OpenClawSetupBadge(status: appState.openClawSetupStatus)
            }

            Text(appState.openClawSetupDescription)
                .font(.system(size: 11))
                .foregroundStyle(DashboardTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(appState.openClawPluginStatusText)
                .font(.system(size: 11))
                .foregroundStyle(pluginStatusColor)
                .fixedSize(horizontal: false, vertical: true)

            Text(appState.openClawGatewayStatusText)
                .font(.system(size: 11))
                .foregroundStyle(DashboardTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(appState.openClawTransparentModeStatusText)
                .font(.system(size: 11))
                .foregroundStyle(DashboardTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Gateway endpoint", text: $appState.openClawGatewayEndpoint)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))

            Picker("Gateway auth", selection: $appState.openClawGatewayAuthMode) {
                ForEach(AppState.OpenClawGatewayAuthMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if appState.openClawGatewayAuthMode == .bearer {
                SecureField("Bearer token", text: $appState.openClawGatewayBearerToken)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }

            Picker("Trace source", selection: $appState.openClawSourceFilter) {
                ForEach(OpenClawTraceSourceFilter.allCases, id: \.self) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 6) {
                Button("Quick Setup") {
                    appState.setupOpenClawTracing()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(appState.openClawPluginStatus == .installing)

                Button("Install Plugin") {
                    appState.installOpenClawDiagnosticsPlugin()
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(appState.openClawPluginStatus == .installing)
            }

            HStack(spacing: 6) {
                Button(appState.isOpenClawGatewayCaptureEnabled ? "Disable Gateway" : "Enable Gateway") {
                    appState.toggleOpenClawGatewayCapture()
                }
                .buttonStyle(GhostButtonStyle())

                Button(appState.isOpenClawTransparentModeEnabled ? "Disable Transparent" : "Enable Transparent") {
                    appState.toggleOpenClawTransparentMode()
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(appState.isApplyingTransparentMode)
            }
        }
    }

    private var pluginStatusColor: Color {
        switch appState.openClawPluginStatus {
        case .installed:
            return DashboardTheme.Colors.accentSuccess
        case .failed:
            return DashboardTheme.Colors.accentError
        case .unknown, .installing:
            return DashboardTheme.Colors.textSecondary
        }
    }
}

private struct OpenClawSetupBadge: View {
    let status: AppState.OpenClawSetupStatus

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background)
            .clipShape(.capsule)
    }

    private var text: String {
        switch status {
        case .notConnected:
            return "Not Connected"
        case .waitingForDiagnostics:
            return "Waiting"
        case .connected:
            return "Connected"
        }
    }

    private var foreground: Color {
        switch status {
        case .connected:
            return DashboardTheme.Colors.accentSuccess
        case .waitingForDiagnostics:
            return DashboardTheme.Colors.accentWarning
        case .notConnected:
            return DashboardTheme.Colors.textSecondary
        }
    }

    private var background: Color {
        switch status {
        case .connected:
            return DashboardTheme.Colors.accentSuccess.opacity(0.08)
        case .waitingForDiagnostics:
            return DashboardTheme.Colors.accentWarning.opacity(0.08)
        case .notConnected:
            return DashboardTheme.Colors.textTertiary.opacity(0.08)
        }
    }
}

private extension Trace {
    var isRecent: Bool { fileTimestamp.timeIntervalSinceNow > -10 }
}
