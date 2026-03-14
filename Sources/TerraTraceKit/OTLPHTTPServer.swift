import Foundation
import Network

#if canImport(OpenTelemetryProtocolExporterCommon)
import OpenTelemetryProtocolExporterCommon
#elseif canImport(OpenTelemetryProtocolExporterGrpc)
import OpenTelemetryProtocolExporterGrpc
#elseif canImport(OpenTelemetryProtocolExporterHttp)
import OpenTelemetryProtocolExporterHttp
#elseif canImport(OpenTelemetryProtocolExporterHTTP)
import OpenTelemetryProtocolExporterHTTP
#endif

public final class OTLPHTTPServer {
  public struct Limits: Sendable {
    public var maxHeaderBytes: Int
    public var maxBodyBytes: Int
    public var headerReadTimeout: TimeInterval
    public var bodyReadTimeout: TimeInterval

    public init(
      maxHeaderBytes: Int = 32 * 1024,
      maxBodyBytes: Int = 10 * 1024 * 1024,
      headerReadTimeout: TimeInterval = 5,
      bodyReadTimeout: TimeInterval = 15
    ) {
      self.maxHeaderBytes = maxHeaderBytes
      self.maxBodyBytes = maxBodyBytes
      self.headerReadTimeout = headerReadTimeout
      self.bodyReadTimeout = bodyReadTimeout
    }
  }

  private static let headerTerminator = Data([13, 10, 13, 10])

  private let decoder: OTLPRequestDecoder
  private let traceStore: TraceStore
  private let limits: Limits
  private let host: String
  private let configuredPort: UInt16
  private let onSpans: (([SpanRecord]) -> Void)?

  private static let maxActiveConnections = 64

  private let queue = DispatchQueue(label: "terra.trace.otlp.httpserver")
  private var listener: NWListener?
  private var activeConnections: [ObjectIdentifier: NWConnection] = [:]
  private var readTimeoutTimers: [ObjectIdentifier: DispatchSourceTimer] = [:]
  private var decodeTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

  public var port: UInt16 {
    listener?.port?.rawValue ?? configuredPort
  }

  public init(
    host: String = "127.0.0.1",
    port: UInt16 = 4318,
    decoder: OTLPRequestDecoder = OTLPRequestDecoder(),
    traceStore: TraceStore,
    limits: Limits = Limits(),
    onSpans: (([SpanRecord]) -> Void)? = nil
  ) {
    self.host = host
    self.configuredPort = port
    self.decoder = decoder
    self.traceStore = traceStore
    self.limits = limits
    self.onSpans = onSpans
  }

  public func start() throws {
    guard listener == nil else { return }

    let parameters = NWParameters.tcp
    let listener: NWListener
    if configuredPort == 0 {
      listener = try NWListener(using: parameters)
    } else if let port = NWEndpoint.Port(rawValue: configuredPort) {
      if shouldBindToHost(host) {
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: port)
        listener = try NWListener(using: parameters)
      } else {
        listener = try NWListener(using: parameters, on: port)
      }
    } else {
      throw NSError(domain: "OTLPHTTPServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid port"])
    }

    listener.stateUpdateHandler = { [weak self] (state: NWListener.State) in
      if case .failed = state {
        self?.stop()
      }
    }

    listener.newConnectionHandler = { [weak self] connection in
      self?.handle(connection)
    }

    self.listener = listener
    listener.start(queue: queue)
  }

  public func stop() {
    queue.async {
      self.listener?.cancel()
      self.listener = nil
      for id in Array(self.activeConnections.keys) {
        self.cleanupConnection(id: id)
      }
    }
  }

  deinit {
    listener?.cancel()
    listener = nil
    for id in Array(activeConnections.keys) {
      cleanupConnection(id: id)
    }
  }

  private func handle(_ connection: NWConnection) {
    guard activeConnections.count < Self.maxActiveConnections else {
      connection.cancel()
      return
    }
    let id = ObjectIdentifier(connection)
    activeConnections[id] = connection

    connection.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .failed, .cancelled:
        self.cleanupConnection(id: id)
      default:
        break
      }
    }

    connection.start(queue: queue)
    receiveHeaders(on: connection, connectionID: id, buffer: Data())
  }

  private func receiveHeaders(on connection: NWConnection, connectionID: ObjectIdentifier, buffer: Data) {
    if buffer.count > limits.maxHeaderBytes {
      sendError(on: connection, status: .headerTooLarge, message: "Request headers too large")
      return
    }

    armReadTimeout(
      for: connectionID,
      connection: connection,
      timeout: limits.headerReadTimeout,
      message: "Timed out while reading request headers"
    )

    let remaining = max(1, limits.maxHeaderBytes - buffer.count)
    connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { [weak self] data, _, isComplete, error in
      guard let self else { return }

      if let error {
        self.sendError(on: connection, status: .internalServerError, message: "Network error: \(error.localizedDescription)")
        return
      }

      var buffer = buffer
      if let data {
        buffer.append(data)
      }

      if let range = buffer.range(of: Self.headerTerminator) {
        let headData = buffer[..<range.lowerBound]
        let bodyStart = buffer[range.upperBound...]
        self.handleRequestHead(
          Data(headData),
          initialBody: Data(bodyStart),
          on: connection,
          connectionID: connectionID
        )
        return
      }

      if isComplete {
        self.sendError(on: connection, status: .badRequest, message: "Incomplete HTTP request")
        return
      }

      self.receiveHeaders(on: connection, connectionID: connectionID, buffer: buffer)
    }
  }

  private func handleRequestHead(
    _ data: Data,
    initialBody: Data,
    on connection: NWConnection,
    connectionID: ObjectIdentifier
  ) {
    let parseResult = parseRequestHead(data)
    switch parseResult {
    case .failure(let error):
      sendError(on: connection, status: error.status, message: error.message, extraHeaders: error.extraHeaders)
    case .success(let head):
      if head.contentLength > limits.maxBodyBytes {
        sendError(on: connection, status: .payloadTooLarge, message: "Payload exceeds max body size")
        return
      }
      if initialBody.count >= head.contentLength {
        let body = head.contentLength == 0 ? Data() : Data(initialBody.prefix(head.contentLength))
        handleBody(body, head: head, on: connection, connectionID: connectionID)
        return
      }
      receiveBody(
        on: connection,
        connectionID: connectionID,
        expectedLength: head.contentLength,
        buffer: initialBody,
        head: head
      )
    }
  }

  private func receiveBody(
    on connection: NWConnection,
    connectionID: ObjectIdentifier,
    expectedLength: Int,
    buffer: Data,
    head: HTTPRequestHead
  ) {
    var buffer = buffer
    if buffer.count >= expectedLength {
      handleBody(Data(buffer.prefix(expectedLength)), head: head, on: connection, connectionID: connectionID)
      return
    }

    armReadTimeout(
      for: connectionID,
      connection: connection,
      timeout: limits.bodyReadTimeout,
      message: "Timed out while reading request body"
    )

    let remaining = expectedLength - buffer.count
    let maxRead = min(remaining, 64 * 1024)
    connection.receive(minimumIncompleteLength: 1, maximumLength: maxRead) { [weak self] data, _, isComplete, error in
      guard let self else { return }

      if let error {
        self.sendError(on: connection, status: .internalServerError, message: "Network error: \(error.localizedDescription)")
        return
      }

      if let data {
        buffer.append(data)
      }

      if buffer.count >= expectedLength {
        self.handleBody(Data(buffer.prefix(expectedLength)), head: head, on: connection, connectionID: connectionID)
        return
      }

      if isComplete {
        self.sendError(on: connection, status: .badRequest, message: "Unexpected end of request body")
        return
      }

      self.receiveBody(
        on: connection,
        connectionID: connectionID,
        expectedLength: expectedLength,
        buffer: buffer,
        head: head
      )
    }
  }

  private func handleBody(
    _ body: Data,
    head: HTTPRequestHead,
    on connection: NWConnection,
    connectionID: ObjectIdentifier
  ) {
    cancelReadTimeout(for: connectionID)
    let task = Task { [weak self] in
      guard let self else { return }
      do {
        try Task.checkCancellation()
        let spans = try decoder.decode(headers: head.headers, body: body)
        try Task.checkCancellation()
        let accepted = await traceStore.ingest(spans)
        try Task.checkCancellation()
        if let onSpans {
          onSpans(accepted)
        }
        self.queue.async {
          guard self.activeConnections[connectionID] != nil else { return }
          self.sendSuccess(on: connection)
        }
      } catch is CancellationError {
        return
      } catch {
        self.queue.async {
          guard self.activeConnections[connectionID] != nil else { return }
          self.sendError(on: connection, status: .badRequest, message: "Invalid OTLP payload")
        }
      }
    }
    decodeTasks[connectionID]?.cancel()
    decodeTasks[connectionID] = task
  }

  private func sendSuccess(on connection: NWConnection) {
    let body = otlpSuccessBody()
    sendResponse(
      on: connection,
      status: .ok,
      headers: [
        "Content-Type": "application/x-protobuf",
        "Connection": "close",
        "Content-Length": "\(body.count)"
      ],
      body: body
    )
  }

  private func sendError(
    on connection: NWConnection,
    status: HTTPStatus,
    message: String,
    extraHeaders: [String: String] = [:]
  ) {
    var headers = extraHeaders
    let body = message.data(using: .utf8) ?? Data()
    headers["Content-Type"] = "text/plain; charset=utf-8"
    headers["Connection"] = "close"
    headers["Content-Length"] = "\(body.count)"
    sendResponse(on: connection, status: status, headers: headers, body: body)
  }

  private func sendResponse(
    on connection: NWConnection,
    status: HTTPStatus,
    headers: [String: String],
    body: Data
  ) {
    var responseLines: [String] = ["HTTP/1.1 \(status.code) \(status.reason)"]
    for (key, value) in headers {
      responseLines.append("\(key): \(value)")
    }
    responseLines.append("")
    responseLines.append("")

    var response = responseLines.joined(separator: "\r\n").data(using: .utf8) ?? Data()
    response.append(body)

    connection.send(content: response, completion: .contentProcessed { [weak self] _ in
      self?.finish(connection)
    })
  }

  private func finish(_ connection: NWConnection) {
    let id = ObjectIdentifier(connection)
    cleanupConnection(id: id)
  }

  private func cleanupConnection(id: ObjectIdentifier) {
    cancelReadTimeout(for: id)
    decodeTasks[id]?.cancel()
    decodeTasks.removeValue(forKey: id)
    if let connection = activeConnections.removeValue(forKey: id) {
      connection.cancel()
    }
  }

  private func cancelReadTimeout(for id: ObjectIdentifier) {
    if let timer = readTimeoutTimers.removeValue(forKey: id) {
      timer.setEventHandler {}
      timer.cancel()
    }
  }

  private func armReadTimeout(
    for id: ObjectIdentifier,
    connection: NWConnection,
    timeout: TimeInterval,
    message: String
  ) {
    guard timeout > 0 else { return }
    cancelReadTimeout(for: id)
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + timeout)
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      guard self.activeConnections[id] != nil else { return }
      self.sendError(on: connection, status: .requestTimeout, message: message)
    }
    readTimeoutTimers[id] = timer
    timer.resume()
  }

  private func otlpSuccessBody() -> Data {
    #if canImport(OpenTelemetryProtocolExporterCommon) || canImport(OpenTelemetryProtocolExporterGrpc) || canImport(OpenTelemetryProtocolExporterHttp) || canImport(OpenTelemetryProtocolExporterHTTP)
    let response = Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceResponse()
    return (try? response.serializedData()) ?? Data()
    #else
    return Data()
    #endif
  }

  private func shouldBindToHost(_ host: String) -> Bool {
    let lowered = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return !lowered.isEmpty && lowered != "0.0.0.0" && lowered != "::"
  }

  private func parseRequestHead(_ data: Data) -> Result<HTTPRequestHead, HTTPParseError> {
    guard let headerString = String(data: data, encoding: .utf8) else {
      return .failure(.badRequest("Invalid header encoding"))
    }

    let normalized = headerString.replacingOccurrences(of: "\r\n", with: "\n")
    let lines = normalized.split(separator: "\n", omittingEmptySubsequences: true)
    guard let requestLine = lines.first else {
      return .failure(.badRequest("Missing request line"))
    }

    let requestParts = requestLine.split(whereSeparator: { $0 == " " || $0 == "\t" })
    guard requestParts.count == 3 else {
      return .failure(.badRequest("Malformed request line: \(requestLine)"))
    }

    let method = String(requestParts[0])
    let path = String(requestParts[1])
    let version = String(requestParts[2])

    guard version == "HTTP/1.1" || version == "HTTP/1.0" else {
      return .failure(.badRequest("Unsupported HTTP version"))
    }

    guard method.uppercased() == "POST" else {
      return .failure(.methodNotAllowed)
    }

    guard path == "/v1/traces" else {
      return .failure(.notFound)
    }

    var headers: [String: String] = [:]

    for line in lines.dropFirst() {
      guard let separatorIndex = line.firstIndex(of: ":") else {
        return .failure(.badRequest("Malformed header line"))
      }
      let name = line[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines)
      let value = line[line.index(after: separatorIndex)...]
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if name.isEmpty {
        return .failure(.badRequest("Malformed header name"))
      }
      let key = name.lowercased()
      if let existing = headers[key] {
        headers[key] = existing + ", " + value
      } else {
        headers[key] = value
      }
    }

    if let expect = headers["expect"], expect.lowercased().contains("100-continue") {
      return .failure(.expectationFailed)
    }

    if let transferEncoding = headers["transfer-encoding"], transferEncoding.lowercased().contains("chunked") {
      return .failure(.lengthRequired)
    }

    guard let contentLengthValue = headers["content-length"] else {
      return .failure(.lengthRequired)
    }

    let trimmedLength = contentLengthValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let lengthToken = trimmedLength.split(separator: ",", maxSplits: 1).first.map { String($0) } ?? trimmedLength
    guard let contentLength = Int(lengthToken.trimmingCharacters(in: .whitespacesAndNewlines)), contentLength >= 0 else {
      return .failure(.badRequest("Invalid Content-Length"))
    }

    return .success(HTTPRequestHead(headers: headers, contentLength: contentLength))
  }
}

// Concurrency safety: mutable state is confined to `queue` and never accessed from other executors.
extension OTLPHTTPServer: @unchecked Sendable {}

private struct HTTPRequestHead {
  let headers: [String: String]
  let contentLength: Int
}

private struct HTTPStatus {
  let code: Int
  let reason: String

  static let ok = HTTPStatus(code: 200, reason: "OK")
  static let badRequest = HTTPStatus(code: 400, reason: "Bad Request")
  static let notFound = HTTPStatus(code: 404, reason: "Not Found")
  static let methodNotAllowed = HTTPStatus(code: 405, reason: "Method Not Allowed")
  static let requestTimeout = HTTPStatus(code: 408, reason: "Request Timeout")
  static let lengthRequired = HTTPStatus(code: 411, reason: "Length Required")
  static let payloadTooLarge = HTTPStatus(code: 413, reason: "Payload Too Large")
  static let expectationFailed = HTTPStatus(code: 417, reason: "Expectation Failed")
  static let headerTooLarge = HTTPStatus(code: 431, reason: "Request Header Fields Too Large")
  static let internalServerError = HTTPStatus(code: 500, reason: "Internal Server Error")
}

private enum HTTPParseError: Error {
  case badRequest(String)
  case notFound
  case methodNotAllowed
  case lengthRequired
  case expectationFailed

  var status: HTTPStatus {
    switch self {
    case .badRequest:
      return .badRequest
    case .notFound:
      return .notFound
    case .methodNotAllowed:
      return .methodNotAllowed
    case .lengthRequired:
      return .lengthRequired
    case .expectationFailed:
      return .expectationFailed
    }
  }

  var message: String {
    switch self {
    case .badRequest(let message):
      return message
    case .notFound:
      return "Unsupported path"
    case .methodNotAllowed:
      return "Unsupported method"
    case .lengthRequired:
      return "Content-Length required"
    case .expectationFailed:
      return "Expect: 100-continue not supported"
    }
  }

  var extraHeaders: [String: String] {
    switch self {
    case .methodNotAllowed:
      return ["Allow": "POST"]
    default:
      return [:]
    }
  }
}
