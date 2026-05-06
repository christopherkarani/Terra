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
    /// Absolute wall-clock deadline for receiving the entire request body once
    /// the head has been parsed. Defends against drip-feed denial-of-service
    /// where a peer never lets the per-chunk timer fire (P0-5). Values <= 0
    /// disable the deadline.
    public var absoluteBodyDeadline: TimeInterval

    public init(
      maxHeaderBytes: Int = 32 * 1024,
      maxBodyBytes: Int = 10 * 1024 * 1024,
      headerReadTimeout: TimeInterval = 5,
      bodyReadTimeout: TimeInterval = 15,
      absoluteBodyDeadline: TimeInterval = 30
    ) {
      self.maxHeaderBytes = maxHeaderBytes
      self.maxBodyBytes = maxBodyBytes
      self.headerReadTimeout = headerReadTimeout
      self.bodyReadTimeout = bodyReadTimeout
      self.absoluteBodyDeadline = absoluteBodyDeadline
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
  private var absoluteBodyTimers: [ObjectIdentifier: DispatchSourceTimer] = [:]
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
      sendError(on: connection, status: .headerTooLarge, message: HTTPStatus.headerTooLarge.reason)
      return
    }

    armReadTimeout(
      for: connectionID,
      connection: connection,
      timeout: limits.headerReadTimeout,
      message: HTTPStatus.requestTimeout.reason
    )

    let remaining = max(1, limits.maxHeaderBytes - buffer.count)
    connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { [weak self] data, _, isComplete, error in
      guard let self else { return }

      if error != nil {
        self.sendError(on: connection, status: .internalServerError, message: HTTPStatus.internalServerError.reason)
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
        self.sendError(on: connection, status: .badRequest, message: HTTPStatus.badRequest.reason)
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
        sendError(on: connection, status: .payloadTooLarge, message: HTTPStatus.payloadTooLarge.reason)
        return
      }
      if initialBody.count >= head.contentLength {
        let body = head.contentLength == 0 ? Data() : Data(initialBody.prefix(head.contentLength))
        handleBody(body, head: head, on: connection, connectionID: connectionID)
        return
      }
      armAbsoluteBodyDeadline(for: connectionID, connection: connection)
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
      message: HTTPStatus.requestTimeout.reason
    )

    let remaining = expectedLength - buffer.count
    let maxRead = min(remaining, 64 * 1024)
    connection.receive(minimumIncompleteLength: 1, maximumLength: maxRead) { [weak self] data, _, isComplete, error in
      guard let self else { return }

      if error != nil {
        self.sendError(on: connection, status: .internalServerError, message: HTTPStatus.internalServerError.reason)
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
        self.sendError(on: connection, status: .badRequest, message: HTTPStatus.badRequest.reason)
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
    cancelAbsoluteBodyDeadline(for: connectionID)
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
          // Generic message — do not surface decoder internals to the client.
          self.sendError(on: connection, status: .badRequest, message: HTTPStatus.badRequest.reason)
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
    cancelAbsoluteBodyDeadline(for: id)
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

  private func cancelAbsoluteBodyDeadline(for id: ObjectIdentifier) {
    if let timer = absoluteBodyTimers.removeValue(forKey: id) {
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

  /// Arms a single absolute deadline for the entire request body. Even if the
  /// per-chunk read timer keeps resetting because bytes trickle in, this timer
  /// guarantees the connection is closed once the absolute budget is spent.
  /// Scheduled on `queue`, so it does not block other connections.
  private func armAbsoluteBodyDeadline(
    for id: ObjectIdentifier,
    connection: NWConnection
  ) {
    guard limits.absoluteBodyDeadline > 0 else { return }
    cancelAbsoluteBodyDeadline(for: id)
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + limits.absoluteBodyDeadline)
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      guard self.activeConnections[id] != nil else { return }
      self.sendError(on: connection, status: .requestTimeout, message: HTTPStatus.requestTimeout.reason)
    }
    absoluteBodyTimers[id] = timer
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
      return .failure(.badRequest)
    }

    // RFC 7230 §3.5: header lines MUST end in CRLF. Reject any bare LF or
    // bare CR that is not part of CRLF — these are classic smuggling
    // primitives because intermediaries normalize them inconsistently.
    let bytes = Array(headerString.utf8)
    var index = 0
    while index < bytes.count {
      let byte = bytes[index]
      if byte == 0x0D { // CR
        guard index + 1 < bytes.count, bytes[index + 1] == 0x0A else {
          return .failure(.badRequest)
        }
        index += 2
        continue
      }
      if byte == 0x0A { // bare LF
        return .failure(.badRequest)
      }
      index += 1
    }

    let lines = headerString.components(separatedBy: "\r\n").filter { !$0.isEmpty }
    guard let requestLine = lines.first else {
      return .failure(.badRequest)
    }

    let requestParts = requestLine.split(whereSeparator: { $0 == " " || $0 == "\t" })
    guard requestParts.count == 3 else {
      return .failure(.badRequest)
    }

    let method = String(requestParts[0])
    let path = String(requestParts[1])
    let version = String(requestParts[2])

    guard version == "HTTP/1.1" || version == "HTTP/1.0" else {
      return .failure(.badRequest)
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
        return .failure(.badRequest)
      }
      let name = line[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines)
      let value = line[line.index(after: separatorIndex)...]
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if name.isEmpty {
        return .failure(.badRequest)
      }
      let key = name.lowercased()
      if let existing = headers[key] {
        if key == "content-length" {
          // RFC 7230 §3.3.2: identical duplicate Content-Length values are
          // allowed. Mismatched values are smuggling-grade ambiguity.
          guard existing.trimmingCharacters(in: .whitespacesAndNewlines) == value else {
            return .failure(.badRequest)
          }
        } else if Self.commaListAllowedHeaders.contains(key) {
          headers[key] = existing + ", " + value
        } else {
          // Default-deny duplicate non-list headers (Host, Authorization,
          // Content-Type, etc.). Concatenating these is a known smuggling
          // primitive; reject instead.
          return .failure(.badRequest)
        }
      } else {
        headers[key] = value
      }
    }

    if let expect = headers["expect"], expect.lowercased().contains("100-continue") {
      return .failure(.expectationFailed)
    }

    let hasTransferEncoding = headers["transfer-encoding"] != nil
    let hasContentLength = headers["content-length"] != nil

    if hasTransferEncoding {
      // RFC 7230 §3.3.3: a request with both Transfer-Encoding and
      // Content-Length is the canonical request-smuggling primitive — close
      // the connection immediately.
      if hasContentLength {
        return .failure(.badRequest)
      }
      // Any non-identity Transfer-Encoding is unsupported here. Per RFC 7230
      // §3.3.1, the correct status is 501 Not Implemented (not 411).
      let value = headers["transfer-encoding"]?.lowercased() ?? ""
      let isIdentityOnly = value
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .allSatisfy { $0 == "identity" }
      if !isIdentityOnly {
        return .failure(.notImplemented)
      }
    }

    guard let contentLengthValue = headers["content-length"] else {
      return .failure(.lengthRequired)
    }

    let trimmedLength = contentLengthValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedLength.contains(","),
          let contentLength = Int(trimmedLength),
          contentLength >= 0 else {
      return .failure(.badRequest)
    }

    return .success(HTTPRequestHead(headers: headers, contentLength: contentLength))
  }

  /// Headers whose canonical form permits comma-separated list values (RFC
  /// 7230 §3.2.2). Duplicates of these headers may safely be concatenated.
  /// Every other header is treated as singleton; duplicates are rejected to
  /// prevent smuggling via inconsistent intermediary behavior.
  private static let commaListAllowedHeaders: Set<String> = [
    "accept",
    "accept-charset",
    "accept-encoding",
    "accept-language",
    "allow",
    "cache-control",
    "connection",
    "content-encoding",
    "content-language",
    "expect",
    "forwarded",
    "if-match",
    "if-none-match",
    "pragma",
    "te",
    "trailer",
    "upgrade",
    "vary",
    "via",
    "warning",
    "x-forwarded-for",
  ]
}

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
  static let notImplemented = HTTPStatus(code: 501, reason: "Not Implemented")
}

/// HTTP head parse failures. Each case maps to a generic, non-echoing status
/// reason — error response bodies must never leak request data (P0-5).
private enum HTTPParseError: Error {
  case badRequest
  case notFound
  case methodNotAllowed
  case lengthRequired
  case expectationFailed
  case notImplemented

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
    case .notImplemented:
      return .notImplemented
    }
  }

  var message: String { status.reason }

  var extraHeaders: [String: String] {
    switch self {
    case .methodNotAllowed:
      return ["Allow": "POST"]
    default:
      return [:]
    }
  }
}
