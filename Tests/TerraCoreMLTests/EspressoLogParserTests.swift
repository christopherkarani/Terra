#if os(macOS)
import Foundation
import Testing
import OpenTelemetryApi
@testable import TerraCoreML

@Suite("EspressoLogParser", .serialized)
struct EspressoLogParserTests {

  @Test("parses well-formed CostModelFeature lines")
  func parseWellFormed() {
    let output = """
    2024-03-01 12:00:00 info: CostModelFeature: name=conv1 type=convolution gFlopCnt=0.12 gflops=45.3 gbps=12.1 runtime_ms=2.65 is_memory_bound=1 work_unit_efficiency=0.85
    2024-03-01 12:00:01 info: CostModelFeature: name=relu1 type=activation gFlopCnt=0.01 gflops=100.0 gbps=50.0 runtime_ms=0.10 is_memory_bound=0 work_unit_efficiency=0.95
    """

    let entries = EspressoLogParser.parse(output)
    #expect(entries.count == 2)

    #expect(entries[0].name == "conv1")
    #expect(entries[0].type == "convolution")
    #expect(entries[0].gFlopCnt == 0.12)
    #expect(entries[0].gflops == 45.3)
    #expect(entries[0].gbps == 12.1)
    #expect(entries[0].runtimeMs == 2.65)
    #expect(entries[0].isMemoryBound == true)
    #expect(entries[0].workUnitEfficiency == 0.85)

    #expect(entries[1].name == "relu1")
    #expect(entries[1].isMemoryBound == false)
  }

  @Test("empty output returns empty result")
  func emptyOutput() {
    let entries = EspressoLogParser.parse("")
    #expect(entries.isEmpty)
  }

  @Test("malformed lines are skipped")
  func malformedLines() {
    let output = """
    This is not a CostModelFeature line
    Another random log message
    """
    let entries = EspressoLogParser.parse(output)
    #expect(entries.isEmpty)
  }

  @Test("summary aggregation math")
  func summaryAggregation() {
    let entries = [
      CostModelEntry(name: "a", type: "conv", gFlopCnt: 1.0, gflops: 10, gbps: 5, runtimeMs: 1, isMemoryBound: true, workUnitEfficiency: 0.8),
      CostModelEntry(name: "b", type: "relu", gFlopCnt: 0.5, gflops: 20, gbps: 10, runtimeMs: 0.5, isMemoryBound: false, workUnitEfficiency: 0.9),
      CostModelEntry(name: "c", type: "pool", gFlopCnt: 0.3, gflops: 15, gbps: 8, runtimeMs: 0.3, isMemoryBound: true, workUnitEfficiency: 0.7),
    ]

    let summary = EspressoLogParser.summarize(entries)
    #expect(summary.totalGFlops == 1.8)
    #expect(summary.memoryBoundCount == 2)
    #expect(summary.computeBoundCount == 1)
    #expect(abs(summary.averageWorkUnitEfficiency - 0.8) < 0.001)
  }

  @Test("summary telemetry attributes")
  func summaryTelemetryAttributes() {
    let entries = [
      CostModelEntry(name: "a", type: "conv", gFlopCnt: 2.0, gflops: 10, gbps: 5, runtimeMs: 1, isMemoryBound: false, workUnitEfficiency: 0.9),
    ]
    let summary = EspressoLogParser.summarize(entries)
    let attrs = summary.telemetryAttributes

    #expect(attrs["terra.espresso.total_gflops"] == AttributeValue.double(2.0))
    #expect(attrs["terra.espresso.memory_bound_ops"] == AttributeValue.int(0))
    #expect(attrs["terra.espresso.compute_bound_ops"] == AttributeValue.int(1))
    #expect(attrs["terra.espresso.avg_work_unit_efficiency"] == AttributeValue.double(0.9))
  }

  @Test("empty entries produce zero summary")
  func emptySummary() {
    let summary = EspressoLogParser.summarize([])
    #expect(summary.totalGFlops == 0)
    #expect(summary.memoryBoundCount == 0)
    #expect(summary.computeBoundCount == 0)
    #expect(summary.averageWorkUnitEfficiency == 0)
  }
}
#endif
