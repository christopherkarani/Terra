import Foundation
import OpenTelemetryApi
import TerraSystemProfiler
import CTerraANEBridge

public struct ANEHardwareMetrics: Sendable, TelemetryAttributeConvertible {
  public let hardwareExecutionTimeNs: UInt64
  public let hostOverheadUs: Double
  public let segmentCount: Int32
  public let fullyANE: Bool
  public let available: Bool

  public var telemetryAttributes: [String: AttributeValue] {
    [
      "terra.ane.hardware_execution_time_ns": .int(Int(hardwareExecutionTimeNs)),
      "terra.ane.host_overhead_us": .double(hostOverheadUs),
      "terra.ane.segment_count": .int(Int(segmentCount)),
      "terra.ane.fully_ane": .bool(fullyANE),
      "terra.ane.available": .bool(available),
    ]
  }

  public init(from cMetrics: terra_ane_metrics_t) {
    self.hardwareExecutionTimeNs = cMetrics.hardware_execution_time_ns
    self.hostOverheadUs = cMetrics.host_overhead_us
    self.segmentCount = cMetrics.segment_count
    self.fullyANE = cMetrics.fully_ane
    self.available = cMetrics.available
  }

  public init(
    hardwareExecutionTimeNs: UInt64,
    hostOverheadUs: Double,
    segmentCount: Int32,
    fullyANE: Bool,
    available: Bool
  ) {
    self.hardwareExecutionTimeNs = hardwareExecutionTimeNs
    self.hostOverheadUs = hostOverheadUs
    self.segmentCount = segmentCount
    self.fullyANE = fullyANE
    self.available = available
  }
}
