import Foundation
import Network
import XCTest
@testable import TerraTraceKit

final class OTLPHTTPServerTests: XCTestCase {
  func testOTLPHTTPServerEnforcesRuntimeAllowlist() async throws {
    let body = try OTLPTestFixtures.serializedRequest()
    let decoder = OTLPRequestDecoder(
      maxBodyBytes: body.count + 1024,
      maxDecompressedBytes: body.count + 1024
    )
    let store = TraceStore(maxSpans: 50)

    let server = OTLPHTTPServer(
      host: "127.0.0.1",
      port: 0,
      decoder: decoder,
      traceStore: store,
      ingestPolicy: .init(
        enforceRuntimeAllowlist: true,
        allowedRuntimes: ["coreml"]
      )
    )

    do {
      try server.start()
    } catch {
      throw XCTSkip("Skipping: unable to bind test server: \(error)")
    }
    defer { server.stop() }

    let actualPort = Int(server.port)
    XCTAssertGreaterThan(actualPort, 0)

    let requestBytes = makeRawRequest(host: "127.0.0.1", port: actualPort, body: body)
    let response = try await sendRawRequest(
      host: "127.0.0.1",
      port: UInt16(actualPort),
      request: requestBytes
    )

    XCTAssertEqual(parseStatusCode(from: response), 403)
    XCTAssertTrue(parseBody(from: response).contains("runtime_not_allowed"))

    let snapshot = await store.snapshot(filter: nil)
    XCTAssertEqual(snapshot.allSpans.count, 0)
  }

  func testOTLPHTTPServerAcceptsAllowedRuntimeBeforeIngest() async throws {
    let body = try OTLPTestFixtures.serializedRequest()
    let decoder = OTLPRequestDecoder(
      maxBodyBytes: body.count + 1024,
      maxDecompressedBytes: body.count + 1024
    )
    let store = TraceStore(maxSpans: 50)

    let server = OTLPHTTPServer(
      host: "127.0.0.1",
      port: 0,
      decoder: decoder,
      traceStore: store,
      ingestPolicy: .init(
        enforceRuntimeAllowlist: true,
        allowedRuntimes: ["http_api"]
      )
    )

    do {
      try server.start()
    } catch {
      throw XCTSkip("Skipping: unable to bind test server: \(error)")
    }
    defer { server.stop() }

    let actualPort = Int(server.port)
    XCTAssertGreaterThan(actualPort, 0)

    let requestBytes = makeRawRequest(host: "127.0.0.1", port: actualPort, body: body)
    let response = try await sendRawRequest(
      host: "127.0.0.1",
      port: UInt16(actualPort),
      request: requestBytes
    )

    XCTAssertEqual(parseStatusCode(from: response), 200)
    let snapshot = await store.snapshot(filter: nil)
    XCTAssertEqual(snapshot.allSpans.count, 2)
  }

  func testOTLPHTTPServerEmitsAuditForMajorSchemaMismatch() async throws {
    let body = try OTLPTestFixtures.serializedRequest(
      resourceAttributes: [
        "service.name": "demo-service",
        "service.version": "1.0.0",
        "terra.semantic.version": "v2",
        "terra.schema.family": "terra",
        "terra.runtime": "http_api",
        "terra.request.id": "request-123",
        "terra.session.id": "session-456",
        "terra.model.fingerprint": "model:gpt-4o:quant:v1",
      ]
    )
    let decoder = OTLPRequestDecoder(
      maxBodyBytes: body.count + 1024,
      maxDecompressedBytes: body.count + 1024
    )
    let store = TraceStore(maxSpans: 50)

    let lock = NSLock()
    var audits: [OTLPHTTPServer.IngestAuditEvent] = []
    let server = OTLPHTTPServer(
      host: "127.0.0.1",
      port: 0,
      decoder: decoder,
      traceStore: store,
      onAudit: { event in
        lock.lock()
        audits.append(event)
        lock.unlock()
      }
    )

    do {
      try server.start()
    } catch {
      throw XCTSkip("Skipping: unable to bind test server: \(error)")
    }
    defer { server.stop() }

    let actualPort = Int(server.port)
    XCTAssertGreaterThan(actualPort, 0)

    let requestBytes = makeRawRequest(host: "127.0.0.1", port: actualPort, body: body)
    let response = try await sendRawRequest(
      host: "127.0.0.1",
      port: UInt16(actualPort),
      request: requestBytes
    )

    XCTAssertEqual(parseStatusCode(from: response), 400)
    XCTAssertTrue(parseBody(from: response).contains("unsupported terra semantic major version"))
    let snapshot = await store.snapshot(filter: nil)
    XCTAssertEqual(snapshot.allSpans.count, 0)

    lock.lock()
    let capturedAudits = audits
    lock.unlock()
    XCTAssertTrue(capturedAudits.contains { $0.kind == .majorVersionMismatch })
  }

  func testOTLPHTTPServerEndToEnd() async throws {
    let body = try OTLPTestFixtures.serializedRequest()
    let decoder = OTLPRequestDecoder(
      maxBodyBytes: body.count + 1024,
      maxDecompressedBytes: body.count + 1024
    )
    let store = TraceStore(maxSpans: 50)

    let onSpansExpectation = expectation(description: "onSpans")
    let server = OTLPHTTPServer(
      host: "127.0.0.1",
      port: 0,
      decoder: decoder,
      traceStore: store
    ) { _ in
      onSpansExpectation.fulfill()
    }

    do {
      try server.start()
    } catch {
      throw XCTSkip("Skipping: unable to bind test server: \(error)")
    }
    defer { server.stop() }

    var actualPort = Int(server.port)
    if actualPort == 0 {
      for _ in 0..<100 where actualPort == 0 {
        try await Task.sleep(nanoseconds: 10_000_000)
        actualPort = Int(server.port)
      }
    }
    guard actualPort > 0 else {
      throw XCTSkip("Skipping: server did not publish an ephemeral port in time")
    }
    let requestBytes = makeRawRequest(
      host: "127.0.0.1",
      port: actualPort,
      body: body
    )

    let response = try await sendRawRequest(
      host: "127.0.0.1",
      port: UInt16(actualPort),
      request: requestBytes
    )

    let statusCode = parseStatusCode(from: response)
    let responseBody = parseBody(from: response)
    XCTAssertEqual(statusCode, 200, "Response body: \(responseBody)")
    await fulfillment(of: [onSpansExpectation], timeout: 5)

    let snapshot = await store.snapshot(filter: nil)
    XCTAssertEqual(snapshot.allSpans.count, 2)

    let renderer = StreamRenderer()
    let lines = renderer.render(spans: snapshot.allSpans)
    XCTAssertFalse(lines.isEmpty)
  }

  func testOTLPHTTPServerRejectsOversizedBody() async throws {
    let store = TraceStore(maxSpans: 10)
    let server = OTLPHTTPServer(
      host: "127.0.0.1",
      port: 0,
      traceStore: store,
      limits: .init(maxHeaderBytes: 32 * 1024, maxBodyBytes: 8)
    )

    do {
      try server.start()
    } catch {
      throw XCTSkip("Skipping: unable to bind test server: \(error)")
    }
    defer { server.stop() }

    let actualPort = Int(server.port)
    XCTAssertGreaterThan(actualPort, 0)

    let oversizedBody = Data(repeating: 0x41, count: 16)
    let request = makeRawRequest(
      host: "127.0.0.1",
      port: actualPort,
      body: oversizedBody
    )
    let response = try await sendRawRequest(
      host: "127.0.0.1",
      port: UInt16(actualPort),
      request: request
    )

    XCTAssertEqual(parseStatusCode(from: response), 413)
    XCTAssertTrue(parseBody(from: response).contains("Payload exceeds max body size"))
  }

  func testOTLPHTTPServerRejectsOversizedHeaders() async throws {
    let store = TraceStore(maxSpans: 10)
    let server = OTLPHTTPServer(
      host: "127.0.0.1",
      port: 0,
      traceStore: store,
      limits: .init(maxHeaderBytes: 128, maxBodyBytes: 10 * 1024 * 1024)
    )

    do {
      try server.start()
    } catch {
      throw XCTSkip("Skipping: unable to bind test server: \(error)")
    }
    defer { server.stop() }

    let actualPort = Int(server.port)
    XCTAssertGreaterThan(actualPort, 0)

    let hugeHeaderValue = String(repeating: "h", count: 512)
    let request = makeRawRequest(
      host: "127.0.0.1",
      port: actualPort,
      body: Data(),
      extraHeaders: ["X-Large: \(hugeHeaderValue)"]
    )
    let response = try await sendRawRequest(
      host: "127.0.0.1",
      port: UInt16(actualPort),
      request: request
    )

    XCTAssertEqual(parseStatusCode(from: response), 431)
    XCTAssertTrue(parseBody(from: response).contains("Request headers too large"))
  }

  func testSendRawRequestReadsFragmentedBodyCompletely() async throws {
    let body = #"{"error":"runtime_not_allowed"}"#
    let serverQueue = DispatchQueue(label: "OTLPHTTPServerTests.fragmented-response")
    let listener = try NWListener(using: .tcp, on: .any)
    let ready = expectation(description: "fragmented response listener ready")
    listener.stateUpdateHandler = { state in
      if case .ready = state {
        ready.fulfill()
      }
    }
    listener.newConnectionHandler = { connection in
      connection.stateUpdateHandler = { state in
        guard case .ready = state else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
          let responseHeaders =
            "HTTP/1.1 403 Forbidden\r\n"
            + "Content-Length: \(body.utf8.count)\r\n"
            + "Connection: close\r\n"
            + "\r\n"
          connection.send(content: Data(responseHeaders.utf8), completion: .contentProcessed { error in
            guard error == nil else {
              connection.cancel()
              return
            }
            serverQueue.asyncAfter(deadline: .now() + 0.05) {
              connection.send(content: Data(body.utf8), completion: .contentProcessed { _ in
                connection.cancel()
              })
            }
          })
        }
      }
      connection.start(queue: serverQueue)
    }

    listener.start(queue: serverQueue)
    await fulfillment(of: [ready], timeout: 2)
    guard let port = listener.port else {
      listener.cancel()
      throw XCTSkip("Skipping: failed to resolve ephemeral listener port")
    }
    defer { listener.cancel() }

    let requestBytes = makeRawRequest(host: "127.0.0.1", port: Int(port.rawValue), body: Data())
    let response = try await sendRawRequest(
      host: "127.0.0.1",
      port: port.rawValue,
      request: requestBytes
    )

    XCTAssertEqual(parseStatusCode(from: response), 403)
    XCTAssertEqual(parseBody(from: response), body)
  }

  func testOTLPHTTPServerMixedConcurrentAllowRejectStressIsDeterministic() async throws {
    let rounds = 2
    let allowedRequests = 18
    let policyRejectRequests = 18
    let schemaRejectRequests = 18

    var observedAcceptedSpanCounts: [Int] = []
    var observedPolicyRejectCounts: [Int] = []
    var observedSchemaRejectCounts: [Int] = []

    for round in 0..<rounds {
      let sampleBody = try OTLPTestFixtures.serializedRequest()
      let decoder = OTLPRequestDecoder(
        maxBodyBytes: sampleBody.count + 4_096,
        maxDecompressedBytes: sampleBody.count + 4_096
      )
      let store = TraceStore(maxSpans: 20_000)

      let lock = NSLock()
      var audits: [OTLPHTTPServer.IngestAuditEvent] = []
      let server = OTLPHTTPServer(
        host: "127.0.0.1",
        port: 0,
        decoder: decoder,
        traceStore: store,
        ingestPolicy: .init(
          enforceRuntimeAllowlist: true,
          allowedRuntimes: ["http_api"]
        ),
        onAudit: { event in
          lock.lock()
          audits.append(event)
          lock.unlock()
        }
      )

      do {
        try server.start()
      } catch {
        throw XCTSkip("Skipping: unable to bind test server: \(error)")
      }

      let actualPort = Int(server.port)
      XCTAssertGreaterThan(actualPort, 0)

      enum RequestKind {
        case allowed
        case policyReject
        case schemaReject
      }

      var requests: [(RequestKind, Data)] = []
      requests.reserveCapacity(allowedRequests + policyRejectRequests + schemaRejectRequests)

      for index in 0..<allowedRequests {
        let body = try makeUniqueSerializedRequest(
          runtime: "http_api",
          semanticVersion: "v1",
          requestID: "allow-\(round)-\(index)",
          seed: round * 10_000 + index
        )
        requests.append((.allowed, body))
      }
      for index in 0..<policyRejectRequests {
        let body = try makeUniqueSerializedRequest(
          runtime: "coreml",
          semanticVersion: "v1",
          requestID: "policy-\(round)-\(index)",
          seed: round * 10_000 + 1_000 + index
        )
        requests.append((.policyReject, body))
      }
      for index in 0..<schemaRejectRequests {
        let body = try makeUniqueSerializedRequest(
          runtime: "http_api",
          semanticVersion: "v2",
          requestID: "schema-\(round)-\(index)",
          seed: round * 10_000 + 2_000 + index
        )
        requests.append((.schemaReject, body))
      }

      let responses = try await withThrowingTaskGroup(of: (RequestKind, Int).self) { group in
        for (kind, body) in requests {
          group.addTask {
            let requestBytes = makeRawRequest(host: "127.0.0.1", port: actualPort, body: body)
            let response = try await sendRawRequest(
              host: "127.0.0.1",
              port: UInt16(actualPort),
              request: requestBytes
            )
            let status = parseStatusCode(from: response) ?? -1
            return (kind, status)
          }
        }

        var values: [(RequestKind, Int)] = []
        values.reserveCapacity(requests.count)
        for try await value in group {
          values.append(value)
        }
        return values
      }

      defer { server.stop() }

      var allowedStatusCount = 0
      var policyStatusCount = 0
      var schemaStatusCount = 0
      for (kind, status) in responses {
        switch kind {
        case .allowed where status == 200:
          allowedStatusCount += 1
        case .policyReject where status == 403:
          policyStatusCount += 1
        case .schemaReject where status == 400:
          schemaStatusCount += 1
        default:
          break
        }
      }

      XCTAssertEqual(allowedStatusCount, allowedRequests, "Round \(round) allowlist requests must be accepted")
      XCTAssertEqual(policyStatusCount, policyRejectRequests, "Round \(round) runtime policy rejects must return 403")
      XCTAssertEqual(schemaStatusCount, schemaRejectRequests, "Round \(round) schema rejects must return 400")

      let snapshot = await store.snapshot(filter: nil)
      let expectedAcceptedSpans = allowedRequests * 2
      XCTAssertEqual(
        snapshot.allSpans.count,
        expectedAcceptedSpans,
        "Round \(round) must ingest only allowed spans before reject paths"
      )

      lock.lock()
      let capturedAudits = audits
      lock.unlock()
      let policyAudits = capturedAudits.filter { $0.kind == .policyReject }.count
      let schemaAudits = capturedAudits.filter { $0.kind == .majorVersionMismatch || $0.kind == .schemaReject }.count

      XCTAssertEqual(policyAudits, policyRejectRequests)
      XCTAssertEqual(schemaAudits, schemaRejectRequests)

      observedAcceptedSpanCounts.append(snapshot.allSpans.count)
      observedPolicyRejectCounts.append(policyStatusCount)
      observedSchemaRejectCounts.append(schemaStatusCount)
    }

    XCTAssertEqual(Set(observedAcceptedSpanCounts), [allowedRequests * 2])
    XCTAssertEqual(Set(observedPolicyRejectCounts), [policyRejectRequests])
    XCTAssertEqual(Set(observedSchemaRejectCounts), [schemaRejectRequests])
  }
}

private func makeUniqueSerializedRequest(
  runtime: String,
  semanticVersion: String,
  requestID: String,
  seed: Int
) throws -> Data {
  var resourceAttributes = OTLPTestFixtures.resourceAttributes
  resourceAttributes["terra.semantic.version"] = semanticVersion
  resourceAttributes["terra.runtime"] = runtime
  resourceAttributes["terra.request.id"] = requestID
  resourceAttributes["terra.session.id"] = "session-\(requestID)"
  resourceAttributes["terra.model.fingerprint"] = "model:stress:\(requestID)"

  var request = OTLPTestFixtures.makeExportRequest(resourceAttributes: resourceAttributes)
  guard
    !request.resourceSpans.isEmpty,
    !request.resourceSpans[0].scopeSpans.isEmpty,
    !request.resourceSpans[0].scopeSpans[0].spans.isEmpty
  else {
    return try request.serializedData()
  }

  let traceIDHex = String(format: "%032llx", UInt64(seed + 1))
  let rootSpanIDHex = String(format: "%016llx", UInt64(seed + 2))
  let childSpanIDHex = String(format: "%016llx", UInt64(seed + 3))

  var scopeSpans = request.resourceSpans[0].scopeSpans[0]
  for index in scopeSpans.spans.indices {
    var span = scopeSpans.spans[index]
    span.traceID = traceIDHex.hexBytesForOTLPTests()
    if index == 0 {
      span.spanID = rootSpanIDHex.hexBytesForOTLPTests()
      span.parentSpanID = Data()
    } else {
      span.spanID = childSpanIDHex.hexBytesForOTLPTests()
      span.parentSpanID = rootSpanIDHex.hexBytesForOTLPTests()
    }
    scopeSpans.spans[index] = span
  }
  request.resourceSpans[0].scopeSpans[0] = scopeSpans

  return try request.serializedData()
}

private extension String {
  func hexBytesForOTLPTests() -> Data {
    var data = Data()
    var index = startIndex
    while index < endIndex {
      let nextIndex = self.index(index, offsetBy: 2)
      let byteString = self[index..<nextIndex]
      if let byte = UInt8(byteString, radix: 16) {
        data.append(byte)
      }
      index = nextIndex
    }
    return data
  }
}

private func makeRawRequest(
  host: String,
  port: Int,
  body: Data,
  extraHeaders: [String] = []
) -> Data {
  var request = "POST /v1/traces HTTP/1.1\r\n"
  request += "Host: \(host):\(port)\r\n"
  request += "Content-Type: application/x-protobuf\r\n"
  request += "Content-Encoding: identity\r\n"
  request += "Content-Length: \(body.count)\r\n"
  for header in extraHeaders {
    request += "\(header)\r\n"
  }
  request += "Connection: close\r\n"
  request += "\r\n"

  var data = Data(request.utf8)
  data.append(body)
  return data
}

private func sendRawRequest(
  host: String,
  port: UInt16,
  request: Data
) async throws -> Data {
  try await withCheckedThrowingContinuation { continuation in
    let lock = NSLock()
    var didResume = false
    func resumeOnce(_ result: Result<Data, Error>) {
      lock.lock()
      if didResume {
        lock.unlock()
        return
      }
      didResume = true
      lock.unlock()
      switch result {
      case .success(let data):
        continuation.resume(returning: data)
      case .failure(let error):
        continuation.resume(throwing: error)
      }
    }

    let connection = NWConnection(
      host: NWEndpoint.Host(host),
      port: NWEndpoint.Port(rawValue: port)!,
      using: .tcp
    )

    connection.stateUpdateHandler = { state in
      switch state {
      case .ready:
        connection.send(content: request, completion: .contentProcessed { error in
          if let error {
            connection.cancel()
            resumeOnce(.failure(error))
            return
          }
          receiveResponse(on: connection, buffer: Data(), resumeOnce: resumeOnce)
        })
      case .failed(let error):
        connection.cancel()
        resumeOnce(.failure(error))
      default:
        break
      }
    }

    connection.start(queue: .global())
  }
}

private func receiveResponse(
  on connection: NWConnection,
  buffer: Data,
  expectedContentLength: Int? = nil,
  headerByteCount: Int? = nil,
  resumeOnce: @escaping (Result<Data, Error>) -> Void
) {
  connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
    if let error {
      connection.cancel()
      resumeOnce(.failure(error))
      return
    }

    var buffer = buffer
    if let data {
      buffer.append(data)
    }

    var expectedContentLength = expectedContentLength
    var headerByteCount = headerByteCount
    if expectedContentLength == nil || headerByteCount == nil {
      if let parsed = parseResponseHeader(buffer) {
        expectedContentLength = parsed.contentLength
        headerByteCount = parsed.headerByteCount
      }
    }

    if let expectedContentLength, let headerByteCount {
      let bodyBytes = max(0, buffer.count - headerByteCount)
      if bodyBytes >= expectedContentLength {
        connection.cancel()
        resumeOnce(.success(buffer))
        return
      }
    }

    if isComplete {
      connection.cancel()
      resumeOnce(.success(buffer))
      return
    }

    receiveResponse(
      on: connection,
      buffer: buffer,
      expectedContentLength: expectedContentLength,
      headerByteCount: headerByteCount,
      resumeOnce: resumeOnce
    )
  }
}

private func parseResponseHeader(_ response: Data) -> (headerByteCount: Int, contentLength: Int?)? {
  guard let headerEnd = response.range(of: Data([13, 10, 13, 10])) else { return nil }
  let headerData = response[..<headerEnd.lowerBound]
  guard let headerString = String(data: headerData, encoding: .utf8) else {
    return (headerByteCount: headerEnd.upperBound, contentLength: nil)
  }

  var contentLength: Int?
  for line in headerString.split(whereSeparator: \.isNewline) {
    let normalized = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.lowercased().hasPrefix("content-length:") {
      let value = normalized.dropFirst("content-length:".count).trimmingCharacters(in: .whitespacesAndNewlines)
      contentLength = Int(value)
      break
    }
  }

  return (headerByteCount: headerEnd.upperBound, contentLength: contentLength)
}

private func parseStatusCode(from response: Data) -> Int? {
  guard let headerEnd = response.range(of: Data([13, 10, 13, 10])) else { return nil }
  let headerData = response[..<headerEnd.lowerBound]
  guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
  guard let statusLine = headerString.split(whereSeparator: { $0 == "\r" || $0 == "\n" }).first else { return nil }
  let parts = statusLine.split(whereSeparator: { $0 == " " || $0 == "\t" })
  guard parts.count >= 2, let code = Int(parts[1]) else { return nil }
  return code
}

private func parseBody(from response: Data) -> String {
  guard let headerEnd = response.range(of: Data([13, 10, 13, 10])) else {
    return "<no body>"
  }
  let bodyData = response[headerEnd.upperBound...]
  return String(data: bodyData, encoding: .utf8) ?? "<non-utf8 body>"
}
