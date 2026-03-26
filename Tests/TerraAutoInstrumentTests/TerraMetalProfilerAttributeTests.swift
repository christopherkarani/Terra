import Testing
import OpenTelemetryApi
@testable import TerraMetalProfiler

@Suite("TerraMetalProfiler attributes", .serialized)
struct TerraMetalProfilerAttributeTests {
  @Test("GPU utilization emits legacy and canonical keys")
  func gpuAliases() {
    let attrs = TerraMetalProfiler.attributes(
      gpuUtilization: 0.64,
      memoryInFlightMB: 128,
      computeTimeMS: 9.5
    )

    #expect(attrs["metal.gpu_utilization"] == AttributeValue.double(0.64))
    #expect(attrs["terra.hw.gpu_occupancy_pct"] == AttributeValue.double(0.64))
    #expect(attrs["metal.memory_in_flight_mb"] == AttributeValue.double(128))
    #expect(attrs["metal.compute_time_ms"] == AttributeValue.double(9.5))
  }
}
