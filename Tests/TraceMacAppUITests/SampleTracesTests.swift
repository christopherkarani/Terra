import Foundation
import Testing
import OpenTelemetrySdk
@testable import TraceMacAppUI

@Suite("SampleTraces Tests")
struct SampleTracesTests {
  private let tempDirectory: URL

  init() throws {
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SampleTracesTests-\(UUID().uuidString)", isDirectory: true)
  }

  private func cleanup() {
    try? FileManager.default.removeItem(at: tempDirectory)
  }

  @Test("writeSampleTrace creates a file in the specified directory")
  func writeSampleTraceCreatesFile() throws {
    try SampleTraces.writeSampleTrace(to: tempDirectory)

    let contents = try FileManager.default.contentsOfDirectory(
      at: tempDirectory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    #expect(contents.count == 1)
    cleanup()
  }

  @Test("Created file contains valid JSON decodable as SpanData array")
  func createdFileContainsValidSpanDataJSON() throws {
    try SampleTraces.writeSampleTrace(to: tempDirectory)

    let contents = try FileManager.default.contentsOfDirectory(
      at: tempDirectory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    let fileURL = try #require(contents.first)
    var data = try Data(contentsOf: fileURL)

    // The file ends with a trailing comma; wrap it as a valid JSON array.
    // Strip trailing comma and whitespace, then wrap in brackets.
    if let lastByte = data.last, lastByte == UInt8(ascii: ",") {
      data = data.dropLast()
    }
    // The content is already a JSON array, so decode directly.
    let spans = try JSONDecoder().decode([SpanData].self, from: data)
    #expect(!spans.isEmpty)
    cleanup()
  }

  @Test("File contains at least 3 spans: agent, inference, tool")
  func fileContainsExpectedSpans() throws {
    try SampleTraces.writeSampleTrace(to: tempDirectory)

    let contents = try FileManager.default.contentsOfDirectory(
      at: tempDirectory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    let fileURL = try #require(contents.first)
    var data = try Data(contentsOf: fileURL)

    if let lastByte = data.last, lastByte == UInt8(ascii: ",") {
      data = data.dropLast()
    }
    let spans = try JSONDecoder().decode([SpanData].self, from: data)

    #expect(spans.count >= 3)

    let names = Set(spans.map(\.name))
    #expect(names.contains("gen_ai.agent"))
    #expect(names.contains("gen_ai.inference"))
    #expect(names.contains("gen_ai.tool"))
    cleanup()
  }
}
