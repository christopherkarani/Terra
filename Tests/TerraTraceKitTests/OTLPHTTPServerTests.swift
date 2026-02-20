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

    let actualPort = Int(server.port)
    XCTAssertGreaterThan(actualPort, 0)
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
