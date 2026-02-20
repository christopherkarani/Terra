import Foundation
import Testing
@testable import TraceMacAppUI

@MainActor
@Test("TraceFormatter formats sub-second and negative durations as milliseconds")
func traceFormatterFormatsMilliseconds() {
  #expect(TraceFormatter.duration(0.256) == "256ms")
  #expect(TraceFormatter.duration(-4.0) == "0ms")
}

@MainActor
@Test("TraceFormatter formats second-level durations with abbreviated units")
func traceFormatterFormatsSeconds() {
  let formatted = TraceFormatter.duration(65)
  #expect(formatted.contains("1"))
  #expect(formatted.contains("m"))
}

@MainActor
@Test("TraceFormatter timestamp always returns display text")
func traceFormatterTimestampIsNonEmpty() {
  let text = TraceFormatter.timestamp(Date(timeIntervalSince1970: 0))
  #expect(!text.isEmpty)
}
