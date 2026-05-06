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
    #expect(attrs["terra.hw.gpu_occupancy_pct"] == AttributeValue.double(64.0))
    #expect(attrs["metal.memory_in_flight_mb"] == AttributeValue.double(128))
    #expect(attrs["metal.compute_time_ms"] == AttributeValue.double(9.5))
  }

  @Test("CoreML route estimates do not masquerade as measured Metal kernel time")
  func estimatedCoreMLRouteAttributes() {
    let attrs = TerraMetalProfiler.estimatedCoreMLRouteAttributes(
      predictionDurationMS: 12.5,
      route: "gpu"
    )

    #expect(attrs["metal.compute_time_ms"] == nil)
    #expect(attrs["terra.coreml.prediction.estimated_gpu_wall_time_ms"] == AttributeValue.double(12.5))
    #expect(attrs["terra.coreml.prediction.estimated_gpu_wall_time_source"] == AttributeValue.string("coreml_prediction_wall_time"))
    #expect(attrs["terra.coreml.prediction.estimated_gpu_route"] == AttributeValue.string("gpu"))
  }
}
