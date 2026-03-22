import Foundation
import Testing
@testable import TerraPowerProfiler

@Suite("PowerMetricsParser")
struct PowerMetricsParserTests {

  @Test("parses sample powermetrics output")
  func parseSample() {
    let output = """
    CPU Power: 1500 mW
    GPU Power: 800 mW
    ANE Power: 200 mW
    Combined Power (CPU + GPU + ANE): 2500 mW
    """

    let sample = PowerMetricsParser.parse(output)
    #expect(sample != nil)
    #expect(sample?.cpuWatts == 1.5)
    #expect(sample?.gpuWatts == 0.8)
    #expect(sample?.aneWatts == 0.2)
    #expect(sample?.packageWatts == 2.5)
  }

  @Test("converts mW to W correctly")
  func milliwattConversion() {
    let output = """
    CPU Power: 3000 mW
    GPU Power: 0 mW
    ANE Power: 0 mW
    """

    let sample = PowerMetricsParser.parse(output)
    #expect(sample?.cpuWatts == 3.0)
    #expect(sample?.gpuWatts == 0.0)
  }

  @Test("returns nil for empty input")
  func emptyInput() {
    let sample = PowerMetricsParser.parse("")
    #expect(sample == nil)
  }

  @Test("returns nil for unrelated output")
  func unrelatedOutput() {
    let sample = PowerMetricsParser.parse("Random log message\nAnother line")
    #expect(sample == nil)
  }

  @Test("handles Package Power label variant")
  func packagePowerVariant() {
    let output = """
    CPU Power: 1000 mW
    GPU Power: 500 mW
    ANE Power: 100 mW
    Package Power: 1600 mW
    """

    let sample = PowerMetricsParser.parse(output)
    #expect(sample?.packageWatts == 1.6)
  }
}
