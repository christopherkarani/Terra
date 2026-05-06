import Foundation
import OpenTelemetryApi
import TerraSystemProfiler

/// Aggregated power metrics summary over a collection of samples.
///
/// ``PowerSummary`` computes average power consumption across all domains from
/// a collection of ``PowerSample`` instances. Attach to traces via
/// ``TelemetryAttributeConvertible``.
///
/// ## Usage
/// ```swift
/// PowerMetricsCollector.start(domains: .all, intervalMs: 500)
/// // ... run workload ...
/// let summary = PowerMetricsCollector.stop()
/// span.setAttributes(summary)
/// ```
///
/// - SeeAlso: ``PowerMetricsCollector``
public struct PowerSummary: Sendable, TelemetryAttributeConvertible {
  /// Collection outcome for the powermetrics session that produced this summary.
  public enum Status: String, Sendable, Codable, Hashable {
    case notStarted = "not_started"
    case completed
    case noSamples = "no_samples"
    case permissionDenied = "permission_denied"
    case failed
  }

  /// Average CPU power consumption in watts, computed over all samples.
  public let averageCpuWatts: Double

  /// Average GPU power consumption in watts, computed over all samples.
  public let averageGpuWatts: Double

  /// Average ANE power consumption in watts, computed over all samples.
  public let averageAneWatts: Double

  /// Average total package power consumption in watts, computed over all samples.
  public let averagePackageWatts: Double

  /// Number of samples aggregated in this summary.
  public let sampleCount: Int

  /// Outcome of the collection session.
  public let status: Status

  /// Human-readable diagnostic from powermetrics stderr or process failure.
  public let diagnosticMessage: String?

  /// Converts the power summary into OpenTelemetry span attributes.
  ///
  /// Produces:
  /// - `terra.power.cpu_watts` (double): Average CPU power in watts.
  /// - `terra.power.gpu_watts` (double): Average GPU power in watts.
  /// - `terra.power.ane_watts` (double): Average ANE power in watts.
  /// - `terra.power.package_watts` (double): Average total package power in watts.
  /// - `terra.power.sample_count` (int): Number of samples in the summary.
  public var telemetryAttributes: [String: AttributeValue] {
    [
      "terra.power.cpu_watts": .double(averageCpuWatts),
      "terra.power.gpu_watts": .double(averageGpuWatts),
      "terra.power.ane_watts": .double(averageAneWatts),
      "terra.power.package_watts": .double(averagePackageWatts),
      "terra.power.sample_count": .int(sampleCount),
      "terra.power.collection_status": .string(status.rawValue),
    ]
  }

  /// Creates a summary by averaging a collection of power samples.
  ///
  /// - Parameter samples: Array of ``PowerSample`` instances to aggregate.
  /// - Returns: ``PowerSummary`` with averaged values; if `samples` is empty,
  ///   returns a summary with all averages set to `0` and `sampleCount` of `0`.
  public static func from(
    _ samples: [PowerSample],
    status explicitStatus: Status? = nil,
    diagnosticMessage: String? = nil
  ) -> PowerSummary {
    let status = explicitStatus ?? (samples.isEmpty ? .noSamples : .completed)
    guard !samples.isEmpty else {
      return PowerSummary(
        averageCpuWatts: 0,
        averageGpuWatts: 0,
        averageAneWatts: 0,
        averagePackageWatts: 0,
        sampleCount: 0,
        status: status,
        diagnosticMessage: diagnosticMessage
      )
    }

    var cpu = 0.0, gpu = 0.0, ane = 0.0, pkg = 0.0
    for s in samples {
      cpu += s.cpuWatts
      gpu += s.gpuWatts
      ane += s.aneWatts
      pkg += s.packageWatts
    }
    let count = Double(samples.count)
    return PowerSummary(
      averageCpuWatts: cpu / count,
      averageGpuWatts: gpu / count,
      averageAneWatts: ane / count,
      averagePackageWatts: pkg / count,
      sampleCount: samples.count,
      status: status,
      diagnosticMessage: diagnosticMessage
    )
  }
}
