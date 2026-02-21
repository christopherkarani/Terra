import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import TerraTraceKit

struct OllamaLogTraceLoadResult {
    let traces: [Trace]
    let totalEntries: Int
}

enum OllamaLogTraceLoader {
    static func loadRecent(
        maxEntries: Int,
        logsDirectoryURL: URL = defaultLogsDirectoryURL()
    ) -> OllamaLogTraceLoadResult {
        guard maxEntries > 0 else {
            return OllamaLogTraceLoadResult(traces: [], totalEntries: 0)
        }
        guard let logFiles = serverLogFiles(in: logsDirectoryURL), !logFiles.isEmpty else {
            return OllamaLogTraceLoadResult(traces: [], totalEntries: 0)
        }

        var parsedEntries: [ParsedEntry] = []
        parsedEntries.reserveCapacity(maxEntries * 2)

        for fileURL in logFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            var lineNumber = 0
            content.enumerateLines { line, _ in
                lineNumber += 1
                guard line.hasPrefix("[GIN]") else { return }
                guard let entry = parse(line: line, fileName: fileURL.lastPathComponent, lineNumber: lineNumber) else {
                    return
                }
                parsedEntries.append(entry)
            }
        }

        if parsedEntries.isEmpty {
            return OllamaLogTraceLoadResult(traces: [], totalEntries: 0)
        }

        parsedEntries.sort { lhs, rhs in
            if lhs.endTime != rhs.endTime {
                return lhs.endTime < rhs.endTime
            }
            if lhs.fileName != rhs.fileName {
                return lhs.fileName < rhs.fileName
            }
            return lhs.lineNumber < rhs.lineNumber
        }

        let totalEntries = parsedEntries.count
        let entriesToRender = Array(parsedEntries.suffix(maxEntries))
        let spans = renderSpans(from: entriesToRender)
        let traces = zip(entriesToRender, spans).compactMap { entry, span in
            makeTrace(from: entry, span: span)
        }
        return OllamaLogTraceLoadResult(traces: traces, totalEntries: totalEntries)
    }

    static func defaultLogsDirectoryURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ollama", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
    }

    private static let lineRegex: NSRegularExpression = {
        // Example:
        // [GIN] 2026/02/18 - 03:24:44 | 200 | 49.20735675s | ::1 | POST "/v1/chat/completions"
        let pattern = #"^\[GIN\]\s+(\d{4}/\d{2}/\d{2})\s+-\s+(\d{2}:\d{2}:\d{2})\s+\|\s+(\d{3})\s+\|\s+([^|]+)\|\s+([^|]+)\|\s+([A-Z]+)\s+"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            fatalError("Invalid Ollama GIN log regex.")
        }
        return regex
    }()

    private static let compositeDurationRegex: NSRegularExpression = {
        let pattern = #"^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+(?:\.\d+)?)s)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            fatalError("Invalid composite duration regex.")
        }
        return regex
    }()

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter
    }()

    private static func serverLogFiles(in directoryURL: URL) -> [URL]? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let filtered = files.filter { fileURL in
            guard fileURL.pathExtension.lowercased() == "log" else { return false }
            return fileURL.lastPathComponent.lowercased().hasPrefix("server")
        }

        return filtered.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
            return lhs.lastPathComponent < rhs.lastPathComponent
        }
    }

    private static func parse(line: String, fileName: String, lineNumber: Int) -> ParsedEntry? {
        let fullRange = NSRange(location: 0, length: line.utf16.count)
        guard let match = lineRegex.firstMatch(in: line, range: fullRange) else { return nil }
        guard match.numberOfRanges == 8 else { return nil }

        guard
            let datePart = substring(in: line, range: match.range(at: 1)),
            let timePart = substring(in: line, range: match.range(at: 2)),
            let statusPart = substring(in: line, range: match.range(at: 3)),
            let durationPart = substring(in: line, range: match.range(at: 4)),
            let ipPart = substring(in: line, range: match.range(at: 5)),
            let methodPart = substring(in: line, range: match.range(at: 6)),
            let pathPart = substring(in: line, range: match.range(at: 7))
        else {
            return nil
        }

        guard let statusCode = Int(statusPart.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        guard let endTime = clockFormatter.date(from: "\(datePart) \(timePart)") else {
            return nil
        }

        guard let duration = parseDuration(durationPart) else {
            return nil
        }

        return ParsedEntry(
            fileName: fileName,
            lineNumber: lineNumber,
            method: methodPart.trimmingCharacters(in: .whitespacesAndNewlines),
            path: pathPart.trimmingCharacters(in: .whitespacesAndNewlines),
            statusCode: statusCode,
            clientIP: ipPart.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: duration,
            endTime: endTime
        )
    }

    private static func parseDuration(_ rawValue: String) -> TimeInterval? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix("µs") {
            let number = String(value.dropLast(2))
            guard let parsed = Double(number) else { return nil }
            return parsed / 1_000_000
        }
        if value.hasSuffix("us") {
            let number = String(value.dropLast(2))
            guard let parsed = Double(number) else { return nil }
            return parsed / 1_000_000
        }
        if value.hasSuffix("ms") {
            let number = String(value.dropLast(2))
            guard let parsed = Double(number) else { return nil }
            return parsed / 1_000
        }
        if value.hasSuffix("s"), !value.contains("m"), !value.contains("h") {
            let number = String(value.dropLast(1))
            return Double(number)
        }

        let fullRange = NSRange(location: 0, length: value.utf16.count)
        guard let match = compositeDurationRegex.firstMatch(in: value, range: fullRange) else { return nil }

        let hours = Int(substring(in: value, range: match.range(at: 1)) ?? "") ?? 0
        let minutes = Int(substring(in: value, range: match.range(at: 2)) ?? "") ?? 0
        let seconds = Double(substring(in: value, range: match.range(at: 3)) ?? "") ?? 0
        let duration = Double(hours * 3600 + minutes * 60) + seconds
        return duration > 0 ? duration : nil
    }

    private static func makeTrace(from entry: ParsedEntry, span: SpanData) -> Trace? {
        let referenceMillis = UInt64(max(0, entry.endTime.timeIntervalSinceReferenceDate * 1000))
        let fileName = "\(referenceMillis)-ollama-\(entry.fileName)-\(entry.lineNumber)"
        return try? Trace(fileName: fileName, spans: [span])
    }

    private static func renderSpans(from entries: [ParsedEntry]) -> [SpanData] {
        guard !entries.isEmpty else { return [] }

        let exporter = CollectingSpanExporter()
        let processor = SimpleSpanProcessor(spanExporter: exporter)
        let tracerProvider = TracerProviderSdk(spanProcessors: [processor])
        let tracer = tracerProvider.get(
            instrumentationName: "com.terra.trace-mac-app.ollama-log-loader",
            instrumentationVersion: "1"
        )

        for entry in entries {
            let endTime = entry.endTime
            let startTime = endTime.addingTimeInterval(-entry.duration)
            let method = entry.method.isEmpty ? "HTTP" : entry.method
            let path = entry.path.isEmpty ? "/api" : entry.path
            let name = "\(method) \(path)"

            let span = tracer
                .spanBuilder(spanName: name)
                .setNoParent()
                .setSpanKind(spanKind: .server)
                .setStartTime(time: startTime)
                .startSpan()

            span.setAttribute(key: "terra.runtime", value: "ollama")
            span.setAttribute(key: "terra.runtime.class", value: "ollama")
            span.setAttribute(key: "terra.runtime.confidence", value: 1.0)
            span.setAttribute(key: "gen_ai.provider.name", value: "ollama")
            span.setAttribute(key: "http.method", value: method)
            span.setAttribute(key: "http.route", value: path)
            span.setAttribute(key: "http.status_code", value: entry.statusCode)
            span.setAttribute(key: "net.peer.ip", value: entry.clientIP)
            span.setAttribute(key: "source.file", value: entry.fileName)
            span.setAttribute(key: "source.line", value: entry.lineNumber)
            span.setAttribute(key: "source.kind", value: "ollama.server.log")

            if entry.statusCode >= 400 {
                span.status = .error(description: "HTTP \(entry.statusCode)")
            } else {
                span.status = .ok
            }

            span.end(time: endTime)
        }

        tracerProvider.forceFlush()
        return exporter.exportedSpans
    }

    private final class CollectingSpanExporter: SpanExporter {
        private let lock = NSLock()
        private(set) var exportedSpans: [SpanData] = []

        func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
            _ = explicitTimeout
            lock.lock()
            defer { lock.unlock() }
            exportedSpans.append(contentsOf: spans)
            return .success
        }

        func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
            _ = explicitTimeout
            return .success
        }

        func shutdown(explicitTimeout: TimeInterval?) {
            _ = explicitTimeout
        }
    }

    private static func substring(in string: String, range: NSRange) -> String? {
        guard range.location != NSNotFound, let swiftRange = Range(range, in: string) else {
            return nil
        }
        return String(string[swiftRange])
    }
}

private struct ParsedEntry {
    let fileName: String
    let lineNumber: Int
    let method: String
    let path: String
    let statusCode: Int
    let clientIP: String
    let duration: TimeInterval
    let endTime: Date
}
