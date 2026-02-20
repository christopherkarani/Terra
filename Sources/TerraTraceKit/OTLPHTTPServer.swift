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
  public struct IngestPolicy: Sendable, Hashable {
    public var enforceRuntimeAllowlist: Bool
    public var allowedRuntimes: Set<String>

    public init(
      enforceRuntimeAllowlist: Bool = true,
      allowedRuntimes: Set<String> = IngestPolicy.defaultAllowedRuntimes
    ) {
      self.enforceRuntimeAllowlist = enforceRuntimeAllowlist
      self.allowedRuntimes = Set(allowedRuntimes.compactMap { Self.canonicalRuntimeValue($0) })
    }

    public static let defaultAllowedRuntimes: Set<String> = [
      "coreml",
      "foundation_models",
      "mlx",
      "ollama",
      "lm_studio",
      "llama_cpp",
      "openclaw_gateway",
      "http_api"
    ]

    static func canonicalRuntimeValue(_ value: String) -> String? {
      let normalized = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
      switch normalized {
      case "coreml":
        return "coreml"
      case "foundation_models", "foundation-models", "foundation models":
        return "foundation_models"
      case "mlx":
        return "mlx"
      case "ollama":
        return "ollama"
      case "lm_studio", "lmstudio", "lm-studio":
        return "lm_studio"
      case "llama_cpp", "llamacpp", "llama-cpp":
        return "llama_cpp"
      case "openclaw_gateway", "openclaw-gateway", "openclaw gateway", "gateway":
        return "openclaw_gateway"
      case "http_api", "http", "httpapi":
        return "http_api"
      default:
        return nil
      }
    }
  }

  public struct IngestAuditEvent: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
      case policyReject = "policy_reject"
      case schemaReject = "schema_reject"
      case majorVersionMismatch = "major_version_mismatch"
    }

    public var kind: Kind
    public var message: String
    public var attributes: [String: String]
    public var timestamp: Date

    public init(
      kind: Kind,
      message: String,
      attributes: [String: String] = [:],
      timestamp: Date = Date()
    ) {
      self.kind = kind
      self.message = message
      self.attributes = attributes
      self.timestamp = timestamp
    }
  }

  public struct Limits: Sendable {
    public var maxHeaderBytes: Int
    public var maxBodyBytes: Int

    public init(maxHeaderBytes: Int = 32 * 1024, maxBodyBytes: Int = 10 * 1024 * 1024) {
      self.maxHeaderBytes = maxHeaderBytes
      self.maxBodyBytes = maxBodyBytes
    }
  }

  private static let headerTerminator = Data([13, 10, 13, 10])

  private let decoder: OTLPRequestDecoder
  private let traceStore: TraceStore
  private let limits: Limits
  private let host: String
  private let configuredPort: UInt16
  private let ingestPolicy: IngestPolicy
  private let onSpans: (([SpanRecord]) -> Void)?
  private let onAudit: ((IngestAuditEvent) -> Void)?

  private let queue = DispatchQueue(label: "terra.trace.otlp.httpserver")
  private var listener: NWListener?
  private var activeConnections: [ObjectIdentifier: NWConnection] = [:]

  public var port: UInt16 {
    listener?.port?.rawValue ?? configuredPort
  }

  public init(
    host: String = "127.0.0.1",
    port: UInt16 = 4318,
    decoder: OTLPRequestDecoder = OTLPRequestDecoder(),
    traceStore: TraceStore,
    limits: Limits = Limits(),
    ingestPolicy: IngestPolicy = .init(),
    onAudit: ((IngestAuditEvent) -> Void)? = nil,
    onSpans: (([SpanRecord]) -> Void)? = nil
  ) {
    self.host = host
    self.configuredPort = port
    self.decoder = decoder
    self.traceStore = traceStore
    self.limits = limits
    self.ingestPolicy = ingestPolicy
    self.onAudit = onAudit
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

    let startStateLock = NSLock()
    let startSemaphore = DispatchSemaphore(value: 0)
    var didSignalStart = false
    var startError: Error?

    func signalStartIfNeeded(error: Error? = nil) {
      startStateLock.lock()
      if didSignalStart {
        startStateLock.unlock()
        return
      }
      didSignalStart = true
      startError = error
      startStateLock.unlock()
      startSemaphore.signal()
    }

    listener.stateUpdateHandler = { [weak self] (state: NWListener.State) in
      switch state {
      case .ready:
        signalStartIfNeeded()
      case .failed(let error):
        self?.stop()
        signalStartIfNeeded(error: error)
      default:
        break
      }
    }

    listener.newConnectionHandler = { [weak self] connection in
      self?.handle(connection)
    }

    self.listener = listener
    listener.start(queue: queue)

    if startSemaphore.wait(timeout: .now() + .seconds(2)) == .timedOut {
      stop()
      throw NSError(
        domain: "OTLPHTTPServer",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for listener readiness"]
      )
    }
    if let startError {
      throw startError
    }
  }

  public func stop() {
    queue.async {
      self.listener?.cancel()
      self.listener = nil
      for connection in self.activeConnections.values {
        connection.cancel()
      }
      self.activeConnections.removeAll()
    }
  }

  private func handle(_ connection: NWConnection) {
    let id = ObjectIdentifier(connection)
    activeConnections[id] = connection

    connection.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .failed, .cancelled:
        self.activeConnections.removeValue(forKey: id)
      default:
        break
      }
    }

    connection.start(queue: queue)
    receiveHeaders(on: connection, buffer: Data())
  }

  private func receiveHeaders(on connection: NWConnection, buffer: Data) {
    if buffer.count > limits.maxHeaderBytes {
      sendError(on: connection, status: .headerTooLarge, message: "Request headers too large")
      return
    }

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
        self.handleRequestHead(Data(headData), initialBody: Data(bodyStart), on: connection)
        return
      }

      if isComplete {
        self.sendError(on: connection, status: .badRequest, message: "Incomplete HTTP request")
        return
      }

      self.receiveHeaders(on: connection, buffer: buffer)
    }
  }

  private func handleRequestHead(_ data: Data, initialBody: Data, on connection: NWConnection) {
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
        handleBody(body, head: head, on: connection)
        return
      }
      receiveBody(on: connection, expectedLength: head.contentLength, buffer: initialBody, head: head)
    }
  }

  private func receiveBody(
    on connection: NWConnection,
    expectedLength: Int,
    buffer: Data,
    head: HTTPRequestHead
  ) {
    var buffer = buffer
    if buffer.count >= expectedLength {
      handleBody(Data(buffer.prefix(expectedLength)), head: head, on: connection)
      return
    }

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
        self.handleBody(Data(buffer.prefix(expectedLength)), head: head, on: connection)
        return
      }

      if isComplete {
        self.sendError(on: connection, status: .badRequest, message: "Unexpected end of request body")
        return
      }

      self.receiveBody(on: connection, expectedLength: expectedLength, buffer: buffer, head: head)
    }
  }

  private func handleBody(_ body: Data, head: HTTPRequestHead, on connection: NWConnection) {
    Task { [weak self] in
      guard let self else { return }
      do {
        let spans = try decoder.decode(headers: head.headers, body: body)
        if let policyReject = evaluateIngestPolicy(for: spans) {
          emitAudit(policyReject.auditEvent)
          self.queue.async {
            self.sendError(
              on: connection,
              status: .forbidden,
              message: policyReject.message
            )
          }
          return
        }
        let accepted = await traceStore.ingest(spans)
        if let onSpans {
          onSpans(accepted)
        }
        self.queue.async { self.sendSuccess(on: connection) }
      } catch let decodeError as OTLPRequestDecoderError {
        let decoderFailure = classifyDecoderFailure(decodeError)
        if let auditEvent = decoderFailure.auditEvent {
          emitAudit(auditEvent)
        }
        self.queue.async {
          self.sendError(
            on: connection,
            status: decoderFailure.status,
            message: decoderFailure.message
          )
        }
      } catch {
        self.queue.async {
          self.sendError(on: connection, status: .badRequest, message: "Invalid OTLP payload")
        }
      }
    }
  }

  private func evaluateIngestPolicy(for spans: [SpanRecord]) -> PolicyReject? {
    guard ingestPolicy.enforceRuntimeAllowlist else { return nil }
    guard !spans.isEmpty else { return nil }

    for span in spans {
      guard let rawRuntime = span.attributes[string: "terra.runtime"],
            let canonicalRuntime = IngestPolicy.canonicalRuntimeValue(rawRuntime) else {
        let message = "Policy rejected OTLP payload: runtime_unresolvable"
        return PolicyReject(
          message: message,
          auditEvent: IngestAuditEvent(
            kind: .policyReject,
            message: message,
            attributes: [
              "reason": "runtime_unresolvable",
              "trace_id": span.traceID.hex,
              "span_id": span.spanID.hex
            ]
          )
        )
      }

      if !ingestPolicy.allowedRuntimes.contains(canonicalRuntime) {
        let message = "Policy rejected OTLP payload: runtime_not_allowed (\(canonicalRuntime))"
        return PolicyReject(
          message: message,
          auditEvent: IngestAuditEvent(
            kind: .policyReject,
            message: message,
            attributes: [
              "reason": "runtime_not_allowed",
              "runtime": canonicalRuntime,
              "trace_id": span.traceID.hex,
              "span_id": span.spanID.hex
            ]
          )
        )
      }
    }

    return nil
  }

  private func classifyDecoderFailure(_ error: OTLPRequestDecoderError) -> DecoderFailure {
    switch error {
    case .unsupportedTerraSchema(let version):
      if isMajorVersionMismatch(version) {
        let message = "Rejected unsupported terra semantic major version: \(version)"
        return DecoderFailure(
          status: .badRequest,
          message: message,
          auditEvent: IngestAuditEvent(
            kind: .majorVersionMismatch,
            message: message,
            attributes: ["terra.semantic.version": version]
          )
        )
      }
      let message = "Rejected unsupported terra schema: \(version)"
      return DecoderFailure(
        status: .badRequest,
        message: message,
        auditEvent: IngestAuditEvent(
          kind: .schemaReject,
          message: message,
          attributes: ["schema": version]
        )
      )
    case .missingTerraSchemaAttributes(let missing):
      return DecoderFailure(
        status: .badRequest,
        message: "Missing required terra schema attributes: \(missing.joined(separator: ", "))",
        auditEvent: IngestAuditEvent(
          kind: .schemaReject,
          message: "Rejected payload with missing required terra attributes",
          attributes: ["missing": missing.joined(separator: ",")]
        )
      )
    default:
      return DecoderFailure(status: .badRequest, message: "Invalid OTLP payload: \(error.description)")
    }
  }

  private func isMajorVersionMismatch(_ value: String) -> Bool {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard normalized.hasPrefix("v") else { return false }
    guard let major = Int(normalized.dropFirst().split(separator: ".").first ?? "") else { return false }
    return major != 1
  }

  private func emitAudit(_ event: IngestAuditEvent) {
    onAudit?(event)
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
    activeConnections.removeValue(forKey: id)
    connection.cancel()
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

private struct HTTPRequestHead {
  let headers: [String: String]
  let contentLength: Int
}

private struct HTTPStatus {
  let code: Int
  let reason: String

  static let ok = HTTPStatus(code: 200, reason: "OK")
  static let badRequest = HTTPStatus(code: 400, reason: "Bad Request")
  static let forbidden = HTTPStatus(code: 403, reason: "Forbidden")
  static let notFound = HTTPStatus(code: 404, reason: "Not Found")
  static let methodNotAllowed = HTTPStatus(code: 405, reason: "Method Not Allowed")
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

private struct PolicyReject {
  let message: String
  let auditEvent: OTLPHTTPServer.IngestAuditEvent
}

private struct DecoderFailure {
  let status: HTTPStatus
  let message: String
  let auditEvent: OTLPHTTPServer.IngestAuditEvent?

  init(
    status: HTTPStatus,
    message: String,
    auditEvent: OTLPHTTPServer.IngestAuditEvent? = nil
  ) {
    self.status = status
    self.message = message
    self.auditEvent = auditEvent
  }
}
