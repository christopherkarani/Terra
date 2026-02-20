import Foundation
import Testing
@testable import TraceMacAppUI

@Suite("OTLPReceiver Tests", .serialized)
struct OTLPReceiverTests {
  private let tracesDirectory: URL

  init() throws {
    tracesDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("OTLPReceiverTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tracesDirectory, withIntermediateDirectories: true)
  }

  private func cleanup() {
    try? FileManager.default.removeItem(at: tracesDirectory)
  }

  @Test("Oversized payload returns HTTP 413")
  func oversizedPayloadReturns413() async throws {
    defer { cleanup() }
    let (receiver, port) = try startReceiver()
    defer { receiver.stop() }

    let payload = Data(repeating: 0x61, count: (4 * 1_048_576) + 2048)
    let (data, response) = try await post(to: port, body: payload)

    let http = try #require(response as? HTTPURLResponse)
    #expect(http.statusCode == 413)
    let body = String(data: data, encoding: .utf8) ?? ""
    #expect(body.contains("Request too large"))
  }

  @Test("Valid OTLP endpoint request returns HTTP 200")
  func validRequestReturns200() async throws {
    defer { cleanup() }
    let (receiver, port) = try startReceiver()
    defer { receiver.stop() }

    let payload = Data("[]".utf8)
    let (_, response) = try await post(to: port, body: payload)
    let http = try #require(response as? HTTPURLResponse)
    #expect(http.statusCode == 200)
  }

  private func startReceiver() throws -> (OTLPReceiver, UInt16) {
    let basePort: UInt16 = 36000
    for offset in 0..<300 {
      let port = basePort + UInt16(offset)
      do {
        let receiver = OTLPReceiver(port: port, tracesDirectoryURL: tracesDirectory)
        try receiver.start()
        // Give the listener a short moment to transition to ready.
        usleep(100_000)
        return (receiver, port)
      } catch {
        continue
      }
    }
    throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey: "Could not bind OTLPReceiver test port"])
  }

  private func post(to port: UInt16, body: Data) async throws -> (Data, URLResponse) {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/traces")!)
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 5
    return try await URLSession.shared.data(for: request)
  }
}
