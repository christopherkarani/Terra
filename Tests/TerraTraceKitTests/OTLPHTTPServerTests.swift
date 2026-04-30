import Foundation
import Network
import XCTest
@testable import TerraTraceKit

final class OTLPHTTPServerTests: XCTestCase {
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

    let actualPort = try await waitForBoundPort(server, timeout: 2.0)
    XCTAssertGreaterThan(actualPort, 0)
    guard actualPort > 0 else {
      XCTFail("Server did not bind to an ephemeral port within timeout")
      return
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

  func testOTLPHTTPServer_headerReadTimeoutReturns408() async throws {
    let store = TraceStore(maxSpans: 50)
    let server = OTLPHTTPServer(
      host: "127.0.0.1",
      port: 0,
      traceStore: store,
      limits: .init(
        maxHeaderBytes: 32 * 1024,
        maxBodyBytes: 10 * 1024 * 1024,
        headerReadTimeout: 0.2,
        bodyReadTimeout: 2
      )
    )

    do {
      try server.start()
    } catch {
      throw XCTSkip("Skipping: unable to bind test server: \(error)")
    }
    defer { server.stop() }

    let actualPort = try await waitForBoundPort(server, timeout: 2.0)
    XCTAssertGreaterThan(actualPort, 0)
    guard actualPort > 0 else {
      XCTFail("Server did not bind to an ephemeral port within timeout")
      return
    }

    var partial = "POST /v1/traces HTTP/1.1\r\n"
    partial += "Host: 127.0.0.1:\(actualPort)\r\n"
    let response = try await sendRawRequest(
      host: "127.0.0.1",
      port: UInt16(actualPort),
      request: Data(partial.utf8)
    )

    XCTAssertEqual(parseStatusCode(from: response), 408, "Response body: \(parseBody(from: response))")
    let snapshot = await store.snapshot(filter: nil)
    XCTAssertTrue(snapshot.allSpans.isEmpty)
  }

  func testOTLPHTTPServer_bodyReadTimeoutReturns408() async throws {
    let fullBody = try OTLPTestFixtures.serializedRequest()
    let partialBody = Data(fullBody.prefix(max(1, fullBody.count / 4)))
    let store = TraceStore(maxSpans: 50)
    let server = OTLPHTTPServer(
      host: "127.0.0.1",
      port: 0,
      traceStore: store,
      limits: .init(
        maxHeaderBytes: 32 * 1024,
        maxBodyBytes: 10 * 1024 * 1024,
        headerReadTimeout: 2,
        bodyReadTimeout: 0.2
      )
    )

    do {
      try server.start()
    } catch {
      throw XCTSkip("Skipping: unable to bind test server: \(error)")
    }
    defer { server.stop() }

    let actualPort = try await waitForBoundPort(server, timeout: 2.0)
    XCTAssertGreaterThan(actualPort, 0)
    guard actualPort > 0 else {
      XCTFail("Server did not bind to an ephemeral port within timeout")
      return
    }

    let requestBytes = makeRawRequestWithContentLength(
      host: "127.0.0.1",
      port: actualPort,
      declaredContentLength: fullBody.count,
      body: partialBody
    )
    let response = try await sendRawRequest(
      host: "127.0.0.1",
      port: UInt16(actualPort),
      request: requestBytes
    )

    XCTAssertEqual(parseStatusCode(from: response), 408, "Response body: \(parseBody(from: response))")
    let snapshot = await store.snapshot(filter: nil)
    XCTAssertTrue(snapshot.allSpans.isEmpty)
  }

  func testOTLPHTTPServer_conflictingContentLengthReturns400() async throws {
    let body = try OTLPTestFixtures.serializedRequest()
    let store = TraceStore(maxSpans: 50)
    let server = OTLPHTTPServer(
      host: "127.0.0.1",
      port: 0,
      traceStore: store
    )

    do {
      try server.start()
    } catch {
      throw XCTSkip("Skipping: unable to bind test server: \(error)")
    }
    defer { server.stop() }

    let actualPort = try await waitForBoundPort(server, timeout: 2.0)
    XCTAssertGreaterThan(actualPort, 0)
    guard actualPort > 0 else {
      XCTFail("Server did not bind to an ephemeral port within timeout")
      return
    }

    let requestBytes = makeRawRequestWithHeaderLines(
      host: "127.0.0.1",
      port: actualPort,
      headerLines: [
        "Content-Type: application/x-protobuf",
        "Content-Encoding: identity",
        "Content-Length: \(body.count)",
        "Content-Length: \(body.count + 1)",
        "Connection: close",
      ],
      body: body
    )
    let response = try await sendRawRequest(
      host: "127.0.0.1",
      port: UInt16(actualPort),
      request: requestBytes
    )

    XCTAssertEqual(parseStatusCode(from: response), 400, "Response body: \(parseBody(from: response))")
    let snapshot = await store.snapshot(filter: nil)
    XCTAssertTrue(snapshot.allSpans.isEmpty)
  }

  // MARK: - P0-5 Request Smuggling Hardening

  func testOTLPHTTPServer_chunkedTransferEncodingReturns501() async throws {
    let body = try OTLPTestFixtures.serializedRequest()
    let store = TraceStore(maxSpans: 50)
    let server = OTLPHTTPServer(host: "127.0.0.1", port: 0, traceStore: store)

    do {
      try server.start()
    } catch {
      throw XCTSkip("Skipping: unable to bind test server: \(error)")
    }
    defer { server.stop() }

    let actualPort = try await waitForBoundPort(server, timeout: 2.0)
    guard actualPort > 0 else {
      XCTFail("Server did not bind to an ephemeral port within timeout")
      return
    }

    // Chunked Transfer-Encoding alone => 501 Not Implemented per RFC 7230.
    let requestBytes = makeRawRequestWithHeaderLines(
      host: "127.0.0.1",
      port: actualPort,
      headerLines: [
        "Content-Type: application/x-protobuf",
        "Transfer-Encoding: chunked",
        "Connection: close",
      ],
      body: body
    )
    let response = try await sendRawRequest(
      host: "127.0.0.1",
      port: UInt16(actualPort),
      request: requestBytes
    )

    XCTAssertEqual(parseStatusCode(from: response), 501, "Response body: \(parseBody(from: response))")
    let snapshot = await store.snapshot(filter: nil)
    XCTAssertTrue(snapshot.allSpans.isEmpty)
  }

  func testOTLPHTTPServer_smugglingTransferEncodingPlusContentLengthReturns400() async throws {
    let body = try OTLPTestFixtures.serializedRequest()
    let store = TraceStore(maxSpans: 50)
    let server = OTLPHTTPServer(host: "127.0.0.1", port: 0, traceStore: store)

    do {
      try server.start()
    } catch {
      throw XCTSkip("Skipping: unable to bind test server: \(error)")
    }
    defer { server.stop() }

    let actualPort = try await waitForBoundPort(server, timeout: 2.0)
    guard actualPort > 0 else {
      XCTFail("Server did not bind to an ephemeral port within timeout")
      return
    }

    // Smuggling primitive: both TE: chunked AND Content-Length present.
    // Must be rejected with 400 to avoid framing ambiguity.
    let requestBytes = makeRawRequestWithHeaderLines(
      host: "127.0.0.1",
      port: actualPort,
      headerLines: [
        "Content-Type: application/x-protobuf",
        "Transfer-Encoding: chunked",
        "Content-Length: \(body.count)",
        "Connection: close",
      ],
      body: body
    )
    let response = try await sendRawRequest(
      host: "127.0.0.1",
      port: UInt16(actualPort),
      request: requestBytes
    )

    XCTAssertEqual(parseStatusCode(from: response), 400, "Response body: \(parseBody(from: response))")
    let snapshot = await store.snapshot(filter: nil)
    XCTAssertTrue(snapshot.allSpans.isEmpty)
  }

  func testOTLPHTTPServer_nonIdentityTransferEncodingReturns501() async throws {
    let body = try OTLPTestFixtures.serializedRequest()
    let store = TraceStore(maxSpans: 50)
    let server = OTLPHTTPServer(host: "127.0.0.1", port: 0, traceStore: store)

    do {
      try server.start()
    } catch {
      throw XCTSkip("Skipping: unable to bind test server: \(error)")
    }
    defer { server.stop() }

    let actualPort = try await waitForBoundPort(server, timeout: 2.0)
    guard actualPort > 0 else {
      XCTFail("Server did not bind to an ephemeral port within timeout")
      return
    }

    // Non-identity, non-chunked TE (e.g., gzip) is also unsupported => 501.
    let requestBytes = makeRawRequestWithHeaderLines(
      host: "127.0.0.1",
      port: actualPort,
      headerLines: [
        "Content-Type: application/x-protobuf",
        "Transfer-Encoding: gzip",
        "Connection: close",
      ],
      body: body
    )
    let response = try await sendRawRequest(
      host: "127.0.0.1",
      port: UInt16(actualPort),
      request: requestBytes
    )

    XCTAssertEqual(parseStatusCode(from: response), 501, "Response body: \(parseBody(from: response))")
  }

  func testOTLPHTTPServer_bareLFInHeadersReturns400() async throws {
    let body = try OTLPTestFixtures.serializedRequest()
    let store = TraceStore(maxSpans: 50)
    let server = OTLPHTTPServer(host: "127.0.0.1", port: 0, traceStore: store)

    do {
      try server.start()
    } catch {
      throw XCTSkip("Skipping: unable to bind test server: \(error)")
    }
    defer { server.stop() }

    let actualPort = try await waitForBoundPort(server, timeout: 2.0)
    guard actualPort > 0 else {
      XCTFail("Server did not bind to an ephemeral port within timeout")
      return
    }

    // Mix bare LF amongst CRLF — must be rejected as malformed framing.
    var request = "POST /v1/traces HTTP/1.1\r\n"
    request += "Host: 127.0.0.1:\(actualPort)\r\n"
    request += "Content-Type: application/x-protobuf\n" // bare LF
    request += "Content-Length: \(body.count)\r\n"
    request += "Connection: close\r\n"
    request += "\r\n"
    var data = Data(request.utf8)
    data.append(body)

    let response = try await sendRawRequest(
      host: "127.0.0.1",
      port: UInt16(actualPort),
      request: data
    )

    XCTAssertEqual(parseStatusCode(from: response), 400, "Response body: \(parseBody(from: response))")
    let snapshot = await store.snapshot(filter: nil)
    XCTAssertTrue(snapshot.allSpans.isEmpty)
  }

  func testOTLPHTTPServer_expectContinueReturns417() async throws {
    let body = try OTLPTestFixtures.serializedRequest()
    let store = TraceStore(maxSpans: 50)
    let server = OTLPHTTPServer(host: "127.0.0.1", port: 0, traceStore: store)

    do {
      try server.start()
    } catch {
      throw XCTSkip("Skipping: unable to bind test server: \(error)")
    }
    defer { server.stop() }

    let actualPort = try await waitForBoundPort(server, timeout: 2.0)
    guard actualPort > 0 else {
      XCTFail("Server did not bind to an ephemeral port within timeout")
      return
    }

    let requestBytes = makeRawRequestWithHeaderLines(
      host: "127.0.0.1",
      port: actualPort,
      headerLines: [
        "Content-Type: application/x-protobuf",
        "Content-Length: \(body.count)",
        "Expect: 100-continue",
        "Connection: close",
      ],
      body: body
    )
    let response = try await sendRawRequest(
      host: "127.0.0.1",
      port: UInt16(actualPort),
      request: requestBytes
    )

    XCTAssertEqual(parseStatusCode(from: response), 417, "Response body: \(parseBody(from: response))")
  }

  func testOTLPHTTPServer_duplicateNonContentLengthHeaderRejected() async throws {
    let body = try OTLPTestFixtures.serializedRequest()
    let store = TraceStore(maxSpans: 50)
    let server = OTLPHTTPServer(host: "127.0.0.1", port: 0, traceStore: store)

    do {
      try server.start()
    } catch {
      throw XCTSkip("Skipping: unable to bind test server: \(error)")
    }
    defer { server.stop() }

    let actualPort = try await waitForBoundPort(server, timeout: 2.0)
    guard actualPort > 0 else {
      XCTFail("Server did not bind to an ephemeral port within timeout")
      return
    }

    // Duplicate Host (singleton header) must be rejected, not concatenated.
    let requestBytes = makeRawRequestWithHeaderLines(
      host: "127.0.0.1",
      port: actualPort,
      headerLines: [
        "Host: attacker.example.com",
        "Content-Type: application/x-protobuf",
        "Content-Length: \(body.count)",
        "Connection: close",
      ],
      body: body
    )
    let response = try await sendRawRequest(
      host: "127.0.0.1",
      port: UInt16(actualPort),
      request: requestBytes
    )

    XCTAssertEqual(parseStatusCode(from: response), 400, "Response body: \(parseBody(from: response))")
  }

  func testOTLPHTTPServer_duplicateAcceptEncodingAllowedAndConcatenated() async throws {
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

    let actualPort = try await waitForBoundPort(server, timeout: 2.0)
    guard actualPort > 0 else {
      XCTFail("Server did not bind to an ephemeral port within timeout")
      return
    }

    // Accept-Encoding is in the comma-list allowlist; duplicates are fine.
    let requestBytes = makeRawRequestWithHeaderLines(
      host: "127.0.0.1",
      port: actualPort,
      headerLines: [
        "Content-Type: application/x-protobuf",
        "Content-Encoding: identity",
        "Accept-Encoding: gzip",
        "Accept-Encoding: deflate",
        "Content-Length: \(body.count)",
        "Connection: close",
      ],
      body: body
    )
    let response = try await sendRawRequest(
      host: "127.0.0.1",
      port: UInt16(actualPort),
      request: requestBytes
    )

    XCTAssertEqual(parseStatusCode(from: response), 200, "Response body: \(parseBody(from: response))")
    await fulfillment(of: [onSpansExpectation], timeout: 5)
  }

  func testOTLPHTTPServer_errorResponseBodiesDoNotEchoRequestData() async throws {
    let store = TraceStore(maxSpans: 50)
    let server = OTLPHTTPServer(host: "127.0.0.1", port: 0, traceStore: store)

    do {
      try server.start()
    } catch {
      throw XCTSkip("Skipping: unable to bind test server: \(error)")
    }
    defer { server.stop() }

    let actualPort = try await waitForBoundPort(server, timeout: 2.0)
    guard actualPort > 0 else {
      XCTFail("Server did not bind to an ephemeral port within timeout")
      return
    }

    // Send a deliberately-malformed request with a recognizable token in the
    // request line. The error body must NOT echo the token.
    let canary = "X-CANARY-TOKEN-LEAK-CHECK"
    let request = "POST /\(canary) HTTP/1.1\r\nHost: 127.0.0.1:\(actualPort)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    let response = try await sendRawRequest(
      host: "127.0.0.1",
      port: UInt16(actualPort),
      request: Data(request.utf8)
    )

    let bodyText = parseBody(from: response)
    XCTAssertFalse(bodyText.contains(canary), "Error body leaked request data: \(bodyText)")
  }

  func testOTLPHTTPServer_absoluteBodyDeadlineEnforced() async throws {
    // Drip-feed the body so the per-chunk timer keeps resetting; the absolute
    // body deadline must still trigger 408.
    let store = TraceStore(maxSpans: 50)
    let server = OTLPHTTPServer(
      host: "127.0.0.1",
      port: 0,
      traceStore: store,
      limits: .init(
        maxHeaderBytes: 32 * 1024,
        maxBodyBytes: 10 * 1024 * 1024,
        headerReadTimeout: 5,
        bodyReadTimeout: 5,
        absoluteBodyDeadline: 0.4
      )
    )

    do {
      try server.start()
    } catch {
      throw XCTSkip("Skipping: unable to bind test server: \(error)")
    }
    defer { server.stop() }

    let actualPort = try await waitForBoundPort(server, timeout: 2.0)
    guard actualPort > 0 else {
      XCTFail("Server did not bind to an ephemeral port within timeout")
      return
    }

    let totalBody = try OTLPTestFixtures.serializedRequest()
    let totalBytes = max(8, totalBody.count)
    do {
      let response = try await sendDripFedRequest(
        host: "127.0.0.1",
        port: UInt16(actualPort),
        contentLength: totalBytes,
        bytesPerTick: 1,
        tickDelay: 0.15,
        maxTicks: 10
      )

      XCTAssertEqual(parseStatusCode(from: response), 408, "Response body: \(parseBody(from: response))")
    } catch {
      let description = String(describing: error)
      guard description.contains("Connection reset by peer") || description.contains("54") else {
        throw error
      }
    }
  }
}

private func waitForBoundPort(
  _ server: OTLPHTTPServer,
  timeout: TimeInterval
) async throws -> Int {
  let deadline = Date().addingTimeInterval(timeout)
  var port = Int(server.port)
  while port == 0 && Date() < deadline {
    try await Task.sleep(nanoseconds: 50_000_000)
    port = Int(server.port)
  }
  return port
}

private func makeRawRequest(host: String, port: Int, body: Data) -> Data {
  var request = "POST /v1/traces HTTP/1.1\r\n"
  request += "Host: \(host):\(port)\r\n"
  request += "Content-Type: application/x-protobuf\r\n"
  request += "Content-Encoding: identity\r\n"
  request += "Content-Length: \(body.count)\r\n"
  request += "Connection: close\r\n"
  request += "\r\n"

  var data = Data(request.utf8)
  data.append(body)
  return data
}

private func makeRawRequestWithContentLength(
  host: String,
  port: Int,
  declaredContentLength: Int,
  body: Data
) -> Data {
  var request = "POST /v1/traces HTTP/1.1\r\n"
  request += "Host: \(host):\(port)\r\n"
  request += "Content-Type: application/x-protobuf\r\n"
  request += "Content-Encoding: identity\r\n"
  request += "Content-Length: \(declaredContentLength)\r\n"
  request += "Connection: close\r\n"
  request += "\r\n"

  var data = Data(request.utf8)
  data.append(body)
  return data
}

private func makeRawRequestWithHeaderLines(
  host: String,
  port: Int,
  headerLines: [String],
  body: Data
) -> Data {
  var request = "POST /v1/traces HTTP/1.1\r\n"
  request += "Host: \(host):\(port)\r\n"
  for headerLine in headerLines {
    request += "\(headerLine)\r\n"
  }
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

    if isComplete {
      connection.cancel()
      resumeOnce(.success(buffer))
      return
    }

    if buffer.range(of: Data([13, 10, 13, 10])) != nil {
      connection.cancel()
      resumeOnce(.success(buffer))
      return
    }

    receiveResponse(on: connection, buffer: buffer, resumeOnce: resumeOnce)
  }
}

private func sendDripFedRequest(
  host: String,
  port: UInt16,
  contentLength: Int,
  bytesPerTick: Int,
  tickDelay: TimeInterval,
  maxTicks: Int
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

    var headerString = "POST /v1/traces HTTP/1.1\r\n"
    headerString += "Host: \(host):\(port)\r\n"
    headerString += "Content-Type: application/x-protobuf\r\n"
    headerString += "Content-Length: \(contentLength)\r\n"
    headerString += "Connection: close\r\n"
    headerString += "\r\n"
    let headerData = Data(headerString.utf8)

    connection.stateUpdateHandler = { state in
      switch state {
      case .ready:
        connection.send(content: headerData, completion: .contentProcessed { error in
          if let error {
            connection.cancel()
            resumeOnce(.failure(error))
            return
          }
          drip(connection: connection, ticksRemaining: maxTicks, bytesPerTick: bytesPerTick, tickDelay: tickDelay) {
            receiveResponse(on: connection, buffer: Data(), resumeOnce: resumeOnce)
          }
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

private func drip(
  connection: NWConnection,
  ticksRemaining: Int,
  bytesPerTick: Int,
  tickDelay: TimeInterval,
  onFinished: @escaping () -> Void
) {
  guard ticksRemaining > 0 else {
    onFinished()
    return
  }
  let payload = Data(repeating: 0x00, count: bytesPerTick)
  connection.send(content: payload, completion: .contentProcessed { _ in
    DispatchQueue.global().asyncAfter(deadline: .now() + tickDelay) {
      drip(
        connection: connection,
        ticksRemaining: ticksRemaining - 1,
        bytesPerTick: bytesPerTick,
        tickDelay: tickDelay,
        onFinished: onFinished
      )
    }
  })
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
