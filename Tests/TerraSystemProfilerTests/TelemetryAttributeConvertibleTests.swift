import Foundation
import Testing
import OpenTelemetryApi
@testable import TerraSystemProfiler

@Suite("TelemetryAttributeConvertible")
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
}
