import OpenTelemetryApi

/// A type whose instances can produce a dictionary of OpenTelemetry span attributes.
///
/// Conforming types provide a canonical mapping of their data into telemetry key-value pairs.
/// This eliminates ad-hoc `telemetryAttributes` / `attributes` computed properties and enables
/// generic aggregation via ``ModelStatsSnapshot``.
public protocol TelemetryAttributeConvertible: Sendable {
  var telemetryAttributes: [String: AttributeValue] { get }
}
