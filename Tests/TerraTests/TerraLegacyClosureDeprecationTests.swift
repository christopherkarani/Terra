import Foundation
import Testing

@Suite("Legacy closure-first deprecations", .serialized)
struct TerraLegacyClosureDeprecationTests {
  @Test("Closure-first legacy factories are explicitly deprecated")
  func closureFirstFactoriesAreDeprecated() throws {
    let fluentAPIPath = projectRoot()
      .appendingPathComponent("Sources")
      .appendingPathComponent("Terra")
      .appendingPathComponent("Terra+FluentAPI.swift")
    let source = try String(contentsOf: fluentAPIPath, encoding: .utf8)

    let signatures = [
      "package static func inference<R>(",
      "package static func stream<R>(",
      "package static func embedding<R>(",
      "package static func agent<R>(",
      "package static func tool<R>(",
      "package static func safetyCheck<R>(",
    ]

    for signature in signatures {
      let ranges = source.ranges(of: signature)
      #expect(!ranges.isEmpty, "Expected to find signature: \(signature)")
      for range in ranges {
        let prefix = source[..<range.lowerBound]
        let context = String(prefix.suffix(220))
        #expect(
          context.contains("@available(*, deprecated"),
          "Expected deprecation annotation before: \(signature)"
        )
      }
    }
  }

  private func projectRoot() -> URL {
    var url = URL(fileURLWithPath: #filePath)
    url.deleteLastPathComponent()
    url.deleteLastPathComponent()
    url.deleteLastPathComponent()
    return url
  }
}

private extension String {
  func ranges(of needle: String) -> [Range<String.Index>] {
    guard !needle.isEmpty else { return [] }
    var found: [Range<String.Index>] = []
    var start = startIndex
    while start < endIndex, let range = range(of: needle, range: start..<endIndex) {
      found.append(range)
      start = range.upperBound
    }
    return found
  }
}
