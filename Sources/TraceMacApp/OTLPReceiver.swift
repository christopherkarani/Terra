import Foundation
import Network
import OpenTelemetrySdk
import TerraTraceKit

/// A lightweight HTTP server that accepts trace data via POST and writes it
/// to the local traces directory in the persistence exporter format.
///
/// MVP scope: accepts `[SpanData]` JSON arrays on `POST /v1/traces`.
/// The listener binds to localhost only (loopback) by default for security.
final class OTLPReceiver {
    private let port: UInt16
    private let tracesDirectoryURL: URL
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.terra.otlp-receiver", qos: .utility)

    /// Called on the main actor when new traces are ingested.
    var onTracesReceived: (@MainActor () -> Void)?

    init(port: UInt16, tracesDirectoryURL: URL) {
        self.port = port
        self.tracesDirectoryURL = tracesDirectoryURL
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw CocoaError(.featureUnsupported,
                userInfo: [NSLocalizedDescriptionKey: "Invalid OTLP receiver port: \(port)"])
        }
        let listener = try NWListener(using: parameters, on: nwPort)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        // Capture port by value to avoid retaining self through the listener.
        let capturedPort = port
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Task { await AppLog.shared.info("otlp.receiver started on port \(capturedPort)") }
            case .failed(let error):
                Task { await AppLog.shared.error("otlp.receiver failed: \(error)") }
            default:
                break
            }
        }

        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    var isRunning: Bool {
        listener?.state == .ready
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(on: connection, accumulated: Data())
    }

    private static let maxRequestSize = 4 * 1_048_576 // 4 MB total

    private func receiveHTTPRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var buffer = accumulated
            if let data {
                buffer.append(data)
            }

            if buffer.count > Self.maxRequestSize {
                self.sendResponse(on: connection, response: Self.errorResponse(413, "Request too large"))
                return
            }

            if let error {
                Task { await AppLog.shared.error("otlp.receiver connection error: \(error)") }
                connection.cancel()
                return
            }

            // Check if we have a complete HTTP request (headers + body)
            if let response = self.tryParseAndRespond(buffer) {
                self.sendResponse(on: connection, response: response)
            } else if isComplete {
                // Connection closed before complete request
                self.sendResponse(on: connection, response: Self.errorResponse(400, "Incomplete request"))
            } else {
                // Need more data
                self.receiveHTTPRequest(on: connection, accumulated: buffer)
            }
        }
    }

    /// Attempts to parse a complete HTTP request from the buffer.
    /// Returns an HTTP response string if parsing is complete, nil if more data is needed.
    private func tryParseAndRespond(_ data: Data) -> String? {
        guard let headerEnd = data.findHTTPHeaderEnd() else {
            return nil // Need more data for headers
        }

        let headerData = data.prefix(headerEnd)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return Self.errorResponse(400, "Invalid header encoding")
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return Self.errorResponse(400, "Missing request line")
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else {
            return Self.errorResponse(400, "Malformed request line")
        }

        let method = String(parts[0])
        let path = String(parts[1])

        // Parse Content-Length (capped to maxRequestSize, reject negative values)
        var contentLength = 0
        for line in lines.dropFirst() {
            if line.lowercased().hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                contentLength = max(0, min(Int(value) ?? 0, Self.maxRequestSize))
            }
        }

        let bodyStart = headerEnd + 4 // Skip \r\n\r\n
        let bodyEnd = bodyStart + contentLength

        guard data.count >= bodyEnd else {
            return nil // Need more body data
        }

        let body = data.subdata(in: bodyStart..<bodyEnd)
        return processRequest(method: method, path: path, body: body)
    }

    private func processRequest(method: String, path: String, body: Data) -> String {
        guard method == "POST" else {
            return Self.errorResponse(405, "Method not allowed")
        }

        guard path == "/v1/traces" else {
            return Self.errorResponse(404, "Not found. Use POST /v1/traces")
        }

        do {
            let spans = try JSONDecoder().decode([SpanData].self, from: body)
            guard !spans.isEmpty else {
                return Self.successResponse("No spans to ingest")
            }

            try writeSpansToFile(spans)

            if let callback = onTracesReceived {
                Task { @MainActor in callback() }
            }

            return Self.successResponse("Ingested \(spans.count) span(s)")
        } catch {
            return Self.errorResponse(400, "Failed to decode spans: \(error.localizedDescription)")
        }
    }

    private func writeSpansToFile(_ spans: [SpanData]) throws {
        try FileManager.default.createDirectory(at: tracesDirectoryURL, withIntermediateDirectories: true)

        // Use the persistence-exporter numeric naming convention and bump on collisions.
        let fileURL = uniqueTraceFileURL()

        let encoder = JSONEncoder()
        let data = try encoder.encode(spans)
        // Append trailing comma to match persistence exporter format
        var fileData = data
        fileData.append(Data(",".utf8))
        try fileData.write(to: fileURL, options: [.atomic])
    }

    private func uniqueTraceFileURL() -> URL {
        let fileManager = FileManager.default
        var timestamp = UInt64(Date.timeIntervalSinceReferenceDate * 1000)
        var fileURL = tracesDirectoryURL.appendingPathComponent("\(timestamp)", isDirectory: false)
        while fileManager.fileExists(atPath: fileURL.path) {
            timestamp += 1
            fileURL = tracesDirectoryURL.appendingPathComponent("\(timestamp)", isDirectory: false)
        }
        return fileURL
    }

    // MARK: - HTTP response helpers

    private func sendResponse(on connection: NWConnection, response: String) {
        let data = Data(response.utf8)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func jsonBody(_ status: String, _ message: String) -> String {
        let payload: [String: String] = ["status": status, "message": message]
        guard let data = try? JSONEncoder().encode(payload),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{\"status\":\"\(status)\"}"
        }
        return string
    }

    private static func successResponse(_ message: String) -> String {
        let body = jsonBody("ok", message)
        return "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    }

    private static func errorResponse(_ code: Int, _ message: String) -> String {
        let status: String
        switch code {
        case 400: status = "Bad Request"
        case 404: status = "Not Found"
        case 405: status = "Method Not Allowed"
        case 413: status = "Payload Too Large"
        default: status = "Error"
        }
        let body = jsonBody("error", message)
        return "HTTP/1.1 \(code) \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    }
}

private extension Data {
    /// Finds the position of the `\r\n\r\n` HTTP header terminator.
    func findHTTPHeaderEnd() -> Int? {
        let separator: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A] // \r\n\r\n
        guard count >= 4 else { return nil }
        for i in 0...(count - 4) {
            if self[startIndex + i] == separator[0]
                && self[startIndex + i + 1] == separator[1]
                && self[startIndex + i + 2] == separator[2]
                && self[startIndex + i + 3] == separator[3]
            {
                return i
            }
        }
        return nil
    }
}
