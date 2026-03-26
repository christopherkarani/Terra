import Foundation
import Testing
import OpenTelemetryApi
@testable import TerraSystemProfiler

@Suite("TelemetryAttributeConvertible", .serialized)
struct TelemetryAttributeConvertibleTests {

  @Test("MemorySnapshot conforms to TelemetryAttributeConvertible")
  func memorySnapshotConformance() {
    let snapshot = TerraSystemProfiler.MemorySnapshot(
      residentBytes: 104_857_600,  // 100 MB
      timestamp: Date()
    )
    let attrs = snapshot.telemetryAttributes
    #expect(attrs["process.memory.resident_bytes"] == AttributeValue.int(104_857_600))
    #expect(attrs["process.memory.resident_mb"] == AttributeValue.double(100.0))
  }

  @Test("protocol can be used as existential")
  func existentialUsage() {
    let snapshot = TerraSystemProfiler.MemorySnapshot(
      residentBytes: 52_428_800,  // 50 MB
      timestamp: Date()
    )
    let provider: any TelemetryAttributeConvertible = snapshot
    let attrs = provider.telemetryAttributes
    #expect(attrs["process.memory.resident_bytes"] == AttributeValue.int(52_428_800))
  }

  @Test("memory delta attributes include canonical Terra aliases")
  func memoryDeltaAliases() {
    let start = TerraSystemProfiler.MemorySnapshot(
      residentBytes: 100 * 1_048_576,
      timestamp: Date()
    )
    let end = TerraSystemProfiler.MemorySnapshot(
      residentBytes: 160 * 1_048_576,
      timestamp: Date()
    )

    let attrs = TerraSystemProfiler.memoryDeltaAttributes(start: start, end: end)
    #expect(attrs["process.memory.resident_delta_mb"] == AttributeValue.double(60.0))
    #expect(attrs["process.memory.peak_mb"] == AttributeValue.double(160.0))
    #expect(attrs["terra.process.memory_peak_mb"] == AttributeValue.double(160.0))
    #expect(attrs["terra.hw.rss_mb"] == AttributeValue.double(160.0))
  }
}
