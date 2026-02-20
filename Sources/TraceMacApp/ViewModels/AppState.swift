import AppKit
import TerraTraceKit
import OpenTelemetrySdk

@Observable
@MainActor
final class AppState {
    private let tracePageSize = 100
    private var requestedTraceFileCount = 100
    private(set) var loadedTraceFileCount = 0
    private(set) var totalTraceFileCount = 0

    enum OpenClawSetupStatus: Equatable {
        case notConnected
        case waitingForDiagnostics
        case connected(traceFiles: Int)
    }

    enum OpenClawPluginStatus: Equatable {
        case unknown
        case installing
        case installed
        case failed(message: String)
    }

    enum OpenClawGatewayAuthMode: String, CaseIterable, Equatable {
        case none
        case bearer

        var title: String {
            switch self {
            case .none:
                return "None"
            case .bearer:
                return "Bearer"
            }
        }
    }

    // MARK: - Published State

    var traces: [Trace] = []
    var selectedTrace: Trace?
    var selectedSpan: SpanData?
    var searchQuery: String = ""
    var isLoading: Bool = false
    var errorMessage: String?
    var openClawPluginStatus: OpenClawPluginStatus = .unknown
    var isOpenClawGatewayCaptureEnabled: Bool = AppSettings.isOpenClawGatewayCaptureEnabled {
        didSet { AppSettings.isOpenClawGatewayCaptureEnabled = isOpenClawGatewayCaptureEnabled }
    }
    var isOpenClawTransparentModeEnabled: Bool = AppSettings.isOpenClawTransparentModeEnabled {
        didSet { AppSettings.isOpenClawTransparentModeEnabled = isOpenClawTransparentModeEnabled }
    }
    var openClawGatewayEndpoint: String = AppSettings.openClawGatewayEndpoint {
        didSet { AppSettings.openClawGatewayEndpoint = openClawGatewayEndpoint }
    }
    var openClawGatewayBearerToken: String = AppSettings.openClawGatewayBearerToken {
        didSet { AppSettings.openClawGatewayBearerToken = openClawGatewayBearerToken }
    }
    var openClawGatewayAuthMode: OpenClawGatewayAuthMode = OpenClawGatewayAuthMode(rawValue: AppSettings.openClawGatewayAuthMode) ?? .none {
        didSet { AppSettings.openClawGatewayAuthMode = openClawGatewayAuthMode.rawValue }
    }
    var openClawSourceFilter: OpenClawTraceSourceFilter = .all
    var runtimeFilter: TraceRuntimeFilter = .all
    var isApplyingTransparentMode: Bool = false
    var openClawTransparentModeLastMessage: String?

    // MARK: - Computed

    var filteredTraces: [Trace] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sourceFiltered = traces.filter { trace in
            switch openClawSourceFilter {
            case .all:
                return true
            case .gateway:
                return trace.openClawSource == .gateway
            case .diagnostics:
                return trace.openClawSource == .diagnostics
            }
        }
        let runtimeFiltered = sourceFiltered.filter { trace in
            switch runtimeFilter {
            case .all:
                return true
            default:
                return trace.detectedRuntime == runtimeFilter
            }
        }
        let sorted = runtimeFiltered.sorted { lhs, rhs in
            if lhs.fileTimestamp != rhs.fileTimestamp {
                return lhs.fileTimestamp > rhs.fileTimestamp
            }
            if lhs.id != rhs.id {
                return lhs.id < rhs.id
            }
            return lhs.traceId.hexString < rhs.traceId.hexString
        }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { trace in
            trace.id.lowercased().contains(query)
                || trace.displayName.lowercased().contains(query)
                || trace.traceId.hexString.lowercased().contains(query)
        }
    }

    var timelineViewModel: TimelineViewModel? {
        guard let selectedTrace else { return nil }
        return TimelineViewModel(trace: selectedTrace)
    }

    var canLoadMoreTraces: Bool {
        loadedTraceFileCount < totalTraceFileCount
    }

    var openClawSetupStatus: OpenClawSetupStatus {
        if !isUsingOpenClawDiagnosticsDirectory {
            return .notConnected
        }

        let traceFiles = openClawTraceFiles().count
        if traceFiles == 0 {
            return .waitingForDiagnostics
        }
        return .connected(traceFiles: traceFiles)
    }

    var openClawSetupDescription: String {
        switch openClawSetupStatus {
        case .notConnected:
            return "Connect Trace to OpenClaw diagnostics, install diagnostics-otel, then start tracing with one click."
        case .waitingForDiagnostics:
            return "Connected. Waiting for OpenClaw diagnostics output (diagnostics.jsonl, gateway.log, or openclaw-YYYY-MM-DD.log)."
        case .connected(let traceFiles):
            return "Connected and monitoring OpenClaw diagnostics (\(traceFiles) file\(traceFiles == 1 ? "" : "s")). New traces load automatically."
        }
    }

    var openClawPluginStatusText: String {
        switch openClawPluginStatus {
        case .unknown:
            return "Plugin status: unknown"
        case .installing:
            return "Plugin status: installing diagnostics-otel…"
        case .installed:
            return "Plugin status: diagnostics-otel ready"
        case .failed(let message):
            return "Plugin status: install failed (\(message))"
        }
    }

    var openClawGatewayStatusText: String {
        guard isOpenClawGatewayCaptureEnabled else {
            return "Gateway capture: disabled"
        }
        let endpoint = openClawGatewayEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointSuffix = endpoint.isEmpty ? "" : " (\(endpoint))"
        if isOTLPReceiverRunning {
            return "Gateway capture: enabled\(endpointSuffix), OTLP receiver listening on :\(AppSettings.otlpReceiverPort)"
        }
        return "Gateway capture: enabled\(endpointSuffix) (start OTLP receiver to ingest live gateway spans)"
    }

    var openClawTransparentModeStatusText: String {
        if isApplyingTransparentMode {
            return "Transparent mode: applying…"
        }
        if isOpenClawTransparentModeEnabled {
            if let openClawTransparentModeLastMessage, !openClawTransparentModeLastMessage.isEmpty {
                return "Transparent mode: enabled (\(openClawTransparentModeLastMessage))"
            }
            return "Transparent mode: enabled"
        }
        if let openClawTransparentModeLastMessage, !openClawTransparentModeLastMessage.isEmpty {
            return "Transparent mode: disabled (\(openClawTransparentModeLastMessage))"
        }
        return "Transparent mode: disabled"
    }

    var isUsingOpenClawDiagnosticsDirectory: Bool {
        AppSettings.tracesDirectoryURL.standardizedFileURL.path
            == AppSettings.openClawDiagnosticsDirectoryURL.standardizedFileURL.path
    }

    @ObservationIgnored
    private var _spanDetailViewModel: SpanDetailViewModel?

    var spanDetailViewModel: SpanDetailViewModel {
        let vm = _spanDetailViewModel ?? {
            let new = SpanDetailViewModel()
            _spanDetailViewModel = new
            return new
        }()
        if let span = selectedSpan {
            vm.select(span: span)
        } else {
            vm.clearSelection()
        }
        return vm
    }

    // MARK: - OTLP Receiver

    var isOTLPReceiverRunning: Bool { otlpReceiver?.isRunning ?? false }

    func startOTLPReceiver() {
        stopOTLPReceiver()
        let port = AppSettings.otlpReceiverPort
        let receiver = OTLPReceiver(port: port, tracesDirectoryURL: AppSettings.tracesDirectoryURL)
        receiver.onTracesReceived = { [weak self] in
            self?.loadTraces()
        }
        do {
            try receiver.start()
            self.otlpReceiver = receiver
            AppSettings.isOTLPReceiverEnabled = true
        } catch {
            errorMessage = "Could not start OTLP receiver on port \(port): \(error.localizedDescription)"
        }
    }

    func stopOTLPReceiver() {
        otlpReceiver?.stop()
        otlpReceiver = nil
        AppSettings.isOTLPReceiverEnabled = false
    }

    // MARK: - Private

    private var watcher: TraceDirectoryWatcher?
    private var otlpReceiver: OTLPReceiver?
    private var loader: TraceLoader
    private let isWatchFolderFeatureEnabled: () -> Bool

    // MARK: - Init

    init(isWatchFolderFeatureEnabled: @escaping () -> Bool = { true }) {
        self.isWatchFolderFeatureEnabled = isWatchFolderFeatureEnabled
        self.loader = Self.makeLoader(for: AppSettings.tracesDirectoryURL)
        loadTraces(resetPagination: true)
        if AppSettings.isWatchingTracesDirectory {
            startWatching()
        }
        if AppSettings.isOTLPReceiverEnabled {
            startOTLPReceiver()
        }
    }

    // MARK: - Actions

    func loadTraces(resetPagination: Bool = false) {
        if resetPagination {
            requestedTraceFileCount = tracePageSize
        } else {
            requestedTraceFileCount = max(tracePageSize, requestedTraceFileCount)
        }
        Task(priority: .background) {
            await self.pruneStaleTracesIfNeeded()
        }
        isLoading = true
        errorMessage = nil
        let loader = self.loader
        Task(priority: .userInitiated) {
            let result: Result<TraceLoadResult, Error>
            do {
                let loaded = try loader.loadTracesWithFailures(maxFiles: requestedTraceFileCount)
                result = .success(loaded)
            } catch {
                result = .failure(error)
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let loaded):
                    self.loadedTraceFileCount = loaded.loadedFileCount
                    self.totalTraceFileCount = loaded.totalFileCount
                    let previousSelectedId = self.selectedTrace?.id
                    self.traces = loaded.traces
                    if let previousSelectedId {
                        self.selectedTrace = loaded.traces.first { $0.id == previousSelectedId }
                    }
                    if self.selectedTrace == nil {
                        self.selectedSpan = nil
                    }
                    if !loaded.failures.isEmpty {
                        let count = loaded.failures.count
                        let noun = count == 1 ? "file" : "files"
                        self.errorMessage = "\(count) trace \(noun) could not be loaded."
                        for (file, error) in loaded.failures {
                            Task { await AppLog.shared.error("trace.load_failure file=\(file.lastPathComponent) error=\(error)") }
                        }
                    }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
                self.isLoading = false
            }
        }
    }

    func selectTrace(_ trace: Trace?) {
        selectedTrace = trace
        selectedSpan = nil
    }

    func selectSpan(_ span: SpanData?) {
        selectedSpan = span
    }

    func loadSampleTraces() {
        do {
            try SampleTraces.writeSampleTrace(to: AppSettings.tracesDirectoryURL)
            loadTraces(resetPagination: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreTraces() {
        guard canLoadMoreTraces else { return }
        requestedTraceFileCount += tracePageSize
        loadTraces()
    }

    func chooseTracesFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.directoryURL = AppSettings.tracesDirectoryURL

        guard panel.runModal() == .OK, let url = panel.url else { return }
        configureTracesDirectory(url)
    }

    func setupOpenClawTracing() {
        configureTracesDirectory(AppSettings.openClawDiagnosticsDirectoryURL)
        installOpenClawDiagnosticsPlugin()
        if !isOpenClawGatewayCaptureEnabled {
            isOpenClawGatewayCaptureEnabled = true
        }
        if !isOTLPReceiverRunning {
            startOTLPReceiver()
        }
        if case .waitingForDiagnostics = openClawSetupStatus {
            openOpenClawApp()
        }
    }

    func useOpenClawDiagnosticsFolder() {
        configureTracesDirectory(AppSettings.openClawDiagnosticsDirectoryURL)
    }

    func toggleOpenClawGatewayCapture() {
        isOpenClawGatewayCaptureEnabled.toggle()
        if isOpenClawGatewayCaptureEnabled {
            if !isOTLPReceiverRunning {
                startOTLPReceiver()
            }
        } else if isOTLPReceiverRunning {
            stopOTLPReceiver()
        }
    }

    func toggleOpenClawTransparentMode() {
        guard !isApplyingTransparentMode else { return }
        isApplyingTransparentMode = true
        let shouldEnable = !isOpenClawTransparentModeEnabled
        let targetPorts = configuredTransparentTargetPorts()

        Task {
            let result: Result<String, OpenClawTransparentModeError> = if shouldEnable {
                await OpenClawTransparentModeManager.enable(proxyPort: 11435, targetPorts: targetPorts)
            } else {
                await OpenClawTransparentModeManager.disable()
            }

            switch result {
            case .success(let message):
                isOpenClawTransparentModeEnabled = shouldEnable
                openClawTransparentModeLastMessage = message
            case .failure(let error):
                let message = error.localizedDescription
                if shouldEnable {
                    isOpenClawTransparentModeEnabled = false
                }
                openClawTransparentModeLastMessage = message
                errorMessage = message
            }
            isApplyingTransparentMode = false
        }
    }

    private func configuredTransparentTargetPorts() -> [Int] {
        var ports = Set([11434, 1234])
        if let url = URL(string: openClawGatewayEndpoint),
           let port = url.port {
            ports.insert(port)
        }
        return Array(ports).sorted()
    }

    func installOpenClawDiagnosticsPlugin() {
        guard openClawPluginStatus != .installing else { return }
        openClawPluginStatus = .installing

        Task {
            let outcome = await Self.ensureOpenClawDiagnosticsPluginInstalled()
            switch outcome {
            case .success:
                self.openClawPluginStatus = .installed
            case .failure(let message):
                self.openClawPluginStatus = .failed(message: message)
            }
        }
    }

    func openOpenClawApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "ai.openclaw.mac") {
            NSWorkspace.shared.open(url)
            return
        }

        let fallback = URL(fileURLWithPath: "/Applications/OpenClaw.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: fallback.path) {
            NSWorkspace.shared.open(fallback)
        }
    }

    func openOpenClawLoggingGuide() {
        guard let url = URL(string: "https://docs.openclaw.ai/platforms/mac/logging") else { return }
        NSWorkspace.shared.open(url)
    }

    func openOpenClawPluginGuide() {
        guard let url = URL(string: "https://docs.openclaw.ai/logging#export-to-opentelemetry") else { return }
        NSWorkspace.shared.open(url)
    }

    func exportSelectedTrace(from window: NSWindow?) {
        guard let trace = selectedTrace else { return }
        TraceExporter.exportTraces([trace], from: window)
    }

    func exportAllTraces(from window: NSWindow?) {
        guard !traces.isEmpty else { return }
        TraceExporter.exportTraces(traces, from: window)
    }

    func openTracesFolder() {
        let url = AppSettings.tracesDirectoryURL
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            errorMessage = "Could not create traces folder: \(error.localizedDescription)"
            return
        }
        NSWorkspace.shared.open(url)
    }

    func startWatching() {
        guard isWatchFolderFeatureEnabled() else {
            stopWatching()
            Task { await AppLog.shared.info("traces.watch_start_blocked reason=license") }
            return
        }
        stopWatching()
        let directoryURL = AppSettings.tracesDirectoryURL
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let watcher = TraceDirectoryWatcher(directoryURL: directoryURL) { [weak self] in
                self?.loadTraces()
            }
            try watcher.start()
            self.watcher = watcher
            AppSettings.isWatchingTracesDirectory = true
        } catch {
            errorMessage = "Could not watch traces folder: \(error.localizedDescription)"
        }
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
        AppSettings.isWatchingTracesDirectory = false
    }

    func configureTracesDirectory(_ directoryURL: URL) {
        AppSettings.tracesDirectoryURL = directoryURL
        loader = Self.makeLoader(for: directoryURL)
        loadTraces(resetPagination: true)
        if AppSettings.isWatchingTracesDirectory {
            startWatching()
        }
    }

    private static func makeLoader(for directoryURL: URL) -> TraceLoader {
        let locator = TraceFileLocator(tracesDirectoryURL: directoryURL)
        return TraceLoader(locator: locator)
    }

    private nonisolated func pruneStaleTracesIfNeeded() async {
        let retentionDays = AppSettings.traceRetentionDays
        guard retentionDays > 0 else { return }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) else { return }
        let directoryURL = AppSettings.tracesDirectoryURL
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: .skipsHiddenFiles
        ) else { return }
        for fileURL in contents {
            guard
                let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                values.isRegularFile == true,
                UInt64(fileURL.lastPathComponent) != nil,
                let modDate = values.contentModificationDate
            else { continue }
            if modDate < cutoff {
                try? FileManager.default.removeItem(at: fileURL)
                let name = fileURL.lastPathComponent
                Task { await AppLog.shared.info("trace.pruned file=\(name) cutoff=\(cutoff)") }
            }
        }
    }

    private func openClawTraceFiles() -> [URL] {
        let directoryURL = AppSettings.openClawDiagnosticsDirectoryURL
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files.filter { url in
            AppSettings.isSupportedOpenClawTraceFileName(url.lastPathComponent)
        }
    }

    private static func ensureOpenClawDiagnosticsPluginInstalled() async -> PluginInstallOutcome {
        let enableAttempt = await runOpenClawCommand([
            "plugins", "enable", "diagnostics-otel"
        ])
        if enableAttempt.isSuccess {
            if enableAttempt.requiresGatewayRestart {
                return .failure("diagnostics-otel enabled. Restart OpenClaw gateway, then Trace will ingest diagnostics output.")
            }
            return .success
        }

        let installAttempt = await runOpenClawCommand([
            "plugins", "install", "@openclaw/diagnostics-otel"
        ])
        if !installAttempt.isSuccess {
            return .failure(installAttempt.humanReadableFailure)
        }

        let enableAfterInstall = await runOpenClawCommand([
            "plugins", "enable", "diagnostics-otel"
        ])
        if enableAfterInstall.isSuccess {
            if enableAfterInstall.requiresGatewayRestart {
                return .failure("diagnostics-otel enabled. Restart OpenClaw gateway, then Trace will ingest diagnostics output.")
            }
            return .success
        }

        return .failure(enableAfterInstall.humanReadableFailure)
    }

    private static func runOpenClawCommand(_ arguments: [String]) async -> CommandResult {
        guard let executablePath = openClawExecutablePath() else {
            return CommandResult(
                status: -1,
                stdout: "",
                stderr: "OpenClaw CLI not found. Expected one of: /opt/homebrew/bin/openclaw, /usr/local/bin/openclaw, /usr/bin/openclaw"
            )
        }

        return await runProcess(
            executablePath: executablePath,
            arguments: arguments
        )
    }

    private static func openClawExecutablePath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/openclaw",
            "/usr/local/bin/openclaw",
            "/usr/bin/openclaw"
        ]

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }

    private static func runProcess(executablePath: String, arguments: [String]) async -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, stdout: "", stderr: error.localizedDescription)
        }

        let terminationStatus: Int32 = await withCheckedContinuation { continuation in
            process.terminationHandler = { runningProcess in
                continuation.resume(returning: runningProcess.terminationStatus)
            }
        }

        let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return CommandResult(status: terminationStatus, stdout: stdout, stderr: stderr)
    }
}

private enum PluginInstallOutcome {
    case success
    case failure(String)
}

private struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String

    var isSuccess: Bool {
        status == 0 && !containsPluginLoadFailure
    }

    var requiresGatewayRestart: Bool {
        combinedOutput.lowercased().contains("restart the gateway to apply")
    }

    private var combinedOutput: String {
        [stdout, stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private var containsPluginLoadFailure: Bool {
        let output = combinedOutput.lowercased()
        return output.contains("failed to load")
            || output.contains("cannot find module")
            || output.contains("npm install failed")
    }

    var humanReadableFailure: String {
        if let pluginLine = firstPluginFailureLine() {
            return pluginLine
        }

        let stderrTrimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderrTrimmed.isEmpty {
            return stderrTrimmed
        }

        let stdoutTrimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stdoutTrimmed.isEmpty {
            return stdoutTrimmed
        }

        return "exit code \(status)"
    }

    private func firstPluginFailureLine() -> String? {
        let lines = combinedOutput
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        for line in lines {
            let normalized = line.lowercased()
            if normalized.contains("failed to load")
                || normalized.contains("cannot find module")
                || normalized.contains("npm install failed")
            {
                return line
            }
        }
        return nil
    }
}
