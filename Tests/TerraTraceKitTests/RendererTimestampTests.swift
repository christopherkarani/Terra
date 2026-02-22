import Foundation

#if canImport(Testing) && canImport(_TestingInternals)
import Testing
@testable import TerraTraceKit

@Test
func streamRendererTimestampUsesUTCWithFractionalSeconds() throws {
  let spans = try decodeFixtureSpans()
  let root = try #require(spans.first { $0.name == "root" })

  let renderer = StreamRenderer()
  let output = renderer.render(spans: [root])

  let line = try #require(output.first)
  let timestampToken = try #require(line.split(separator: " ").first)
  let timestamp = String(timestampToken)
  let expected = expectedTimestamp(nanos: root.endTimeUnixNano)
  let local = localTimestamp(nanos: root.endTimeUnixNano)

  #expect(timestamp == expected)
  #expect(timestamp.contains("."))
  #expect(timestamp.hasSuffix("Z"))
  if TimeZone.current.secondsFromGMT() != 0 {
    #expect(timestamp != local)
  }
}

@Test
func streamRendererTimestampStableUnderConcurrentRendering() async throws {
  let spans = try decodeFixtureSpans()
  let renderer = StreamRenderer()
  let expected = renderer.render(spans: spans)

  let iterations = 64
  let results = try await withThrowingTaskGroup(of: [String].self) { group in
    for _ in 0..<iterations {
      group.addTask {
        renderer.render(spans: spans)
      }
    }

    var outputs: [[String]] = []
    outputs.reserveCapacity(iterations)
    for try await output in group {
      outputs.append(output)
    }
    return outputs
  }

  for output in results {
    #expect(output == expected)
  }
}

@Test
func treeRendererUsesDurationFormat() async throws {
  let spans = try decodeFixtureSpans()
  let store = TraceStore()
  _ = await store.ingest(spans)
  let snapshot = await store.snapshot()

  let renderer = TreeRenderer()
  let output = renderer.render(snapshot: snapshot)
  let lines = output.split(separator: "\n").map(String.init)
  let spanLine = lines.first { $0.contains("root") }
  let tokens = spanLine?.split(separator: " ") ?? []

  #expect(tokens.count >= 3)
  let durationToken = tokens.dropFirst(2).first
  #expect(durationToken?.hasSuffix("ms") == true)
}

private func decodeFixtureSpans() throws -> [SpanRecord] {
  let body = try OTLPTestFixtures.serializedRequest()
  let decoder = OTLPRequestDecoder(maxBodyBytes: 1_000_000, maxDecompressedBytes: 1_000_000)
  return try decoder.decode(body: body, headers: ["Content-Encoding": "identity"])
}

private func expectedTimestamp(nanos: UInt64) -> String {
  guard nanos > 0 else { return "0" }
  let seconds = Double(nanos) / 1_000_000_000
  let date = Date(timeIntervalSince1970: seconds)
  return testTimestampFormatter.string(from: date)
}

private func localTimestamp(nanos: UInt64) -> String {
  guard nanos > 0 else { return "0" }
  let seconds = Double(nanos) / 1_000_000_000
  let date = Date(timeIntervalSince1970: seconds)
  return localTimestampFormatter.string(from: date)
}

private let testTimestampFormatter: ISO8601DateFormatter = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  formatter.timeZone = TimeZone(secondsFromGMT: 0)
  return formatter
}()

private let localTimestampFormatter: ISO8601DateFormatter = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  formatter.timeZone = TimeZone.current
  return formatter
}()
#endif
