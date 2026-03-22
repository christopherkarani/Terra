import OpenTelemetryApi

/// A type whose instances can produce a dictionary of OpenTelemetry span attributes.
///
/// Conforming types provide a canonical mapping of their data into telemetry key-value pairs.
/// This eliminates ad-hoc `telemetryAttributes` / `attributes` computed properties and enables
/// generic aggregation via ``ModelStatsSnapshot``.
///
/// ## Conforming Types
///
/// The following Terra types conform to `TelemetryAttributeConvertible`:
/// - ``TerraSystemProfiler/MemorySnapshot``
/// - ``ThermalProfile``
/// - ``ANEHardwareMetrics``
/// - ``PowerSummary``
///
/// ## Example
///
/// ```swift
/// struct MyMetrics: TelemetryAttributeConvertible {
///     let latencyMs: Double
///
///     var telemetryAttributes: [String: AttributeValue] {
///         ["my.latency_ms": .double(latencyMs)]
///     }
/// }
/// ```
public protocol TelemetryAttributeConvertible: Sendable {
  /// A dictionary of OpenTelemetry attribute key-value pairs.
  var telemetryAttributes: [String: AttributeValue] { get }
}
