import Foundation
import OpenTelemetryApi
import TerraSystemProfiler
import CTerraANEBridge

/// Hardware metrics captured from the Neural Engine.
///
/// Contains execution timing and metadata from the ANE. Attach these metrics
/// to your inference traces via ``TelemetryAttributeConvertible``.
public struct ANEHardwareMetrics: Sendable, TelemetryAttributeConvertible {
  /// ANE hardware execution time in nanoseconds.
  public let hardwareExecutionTimeNs: UInt64

  /// Host CPU overhead in microseconds.
  public let hostOverheadUs: Double

  /// Number of ANE program segments executed.
  public let segmentCount: Int32

  /// Whether the entire operation ran on the ANE.
  public let fullyANE: Bool

  /// Whether ANE hardware is available on this device.
  public let available: Bool

  /// Converts the ANE hardware metrics into OpenTelemetry span attributes.
  ///
  /// Produces:
  /// - `terra.ane.hardware_execution_time_ns` (int): ANE execution time in nanoseconds.
  /// - `terra.ane.host_overhead_us` (double): Host CPU overhead in microseconds.
  /// - `terra.ane.segment_count` (int): Number of ANE program segments executed.
  /// - `terra.ane.fully_ane` (bool): Whether the entire operation ran on the ANE.
  /// - `terra.ane.available` (bool): Whether ANE hardware is available on this device.
  public var telemetryAttributes: [String: AttributeValue] {
    [
      "terra.ane.hardware_execution_time_ns": .int(Int(hardwareExecutionTimeNs)),
      "terra.ane.host_overhead_us": .double(hostOverheadUs),
      "terra.ane.segment_count": .int(Int(segmentCount)),
      "terra.ane.fully_ane": .bool(fullyANE),
      "terra.ane.available": .bool(available),
    ]
  }

  /// Creates ANE hardware metrics from the C bridge metrics structure.
  ///
  /// - Parameter cMetrics: The C struct (``terra_ane_metrics_t``) returned by the bridge.
  public init(from cMetrics: terra_ane_metrics_t) {
    self.hardwareExecutionTimeNs = cMetrics.hardware_execution_time_ns
    self.hostOverheadUs = cMetrics.host_overhead_us
    self.segmentCount = cMetrics.segment_count
    self.fullyANE = cMetrics.fully_ane
    self.available = cMetrics.available
  }

  /// Creates ANE hardware metrics with explicit values.
  ///
  /// - Parameters:
  ///   - hardwareExecutionTimeNs: ANE hardware execution time in nanoseconds.
  ///   - hostOverheadUs: Host CPU overhead in microseconds.
  ///   - segmentCount: Number of ANE program segments executed.
  ///   - fullyANE: Whether the entire operation ran on the ANE.
  ///   - available: Whether ANE hardware is available on this device.
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
