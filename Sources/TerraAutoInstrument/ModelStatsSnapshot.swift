import Foundation
import OpenTelemetryApi
import TerraSystemProfiler

/// Aggregates telemetry attributes from multiple profiler results.
///
/// `ModelStatsSnapshot` conforms to `TelemetryAttributeConvertible`, allowing any
/// number of profiler results to be merged into a single flat dictionary of
/// OpenTelemetry attribute key-value pairs. This struct is the canonical return type
/// for the unified model stats API.
///
/// Open for extension without modification — any new profiler just needs
/// `TelemetryAttributeConvertible` conformance to participate.
///
/// ```swift
/// let snapshot = ModelStatsSnapshot(
///     memoryStats,    // from TerraSystemProfiler
///     metalStats,     // from TerraMetalProfiler
///     thermalState    // from ThermalMonitor
/// )
/// let attrs = snapshot.telemetryAttributes
/// ```
public struct ModelStatsSnapshot: Sendable, TelemetryAttributeConvertible {
  private let providers: [any TelemetryAttributeConvertible]

  /// Merges telemetry attributes from all registered profilers into a single dictionary.
  ///
  /// When multiple profilers provide the same attribute key, the later provider's
  /// value takes precedence (last-wins merge strategy).
  public var telemetryAttributes: [String: AttributeValue] {
    providers.reduce(into: [:]) { result, provider in
      result.merge(provider.telemetryAttributes) { _, new in new }
    }
  }

  /// Creates a snapshot from a variadic list of profiler results.
  ///
  /// - Parameter providers: One or more profiler results conforming to `TelemetryAttributeConvertible`.
  public init(_ providers: any TelemetryAttributeConvertible...) {
    self.providers = providers
  }

  /// Creates a snapshot from an array of profiler results.
  ///
  /// - Parameter providers: An array of profiler results conforming to `TelemetryAttributeConvertible`.
  public init(providers: [any TelemetryAttributeConvertible]) {
    self.providers = providers
  }
}
