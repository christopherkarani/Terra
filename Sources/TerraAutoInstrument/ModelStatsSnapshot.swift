import Foundation
import OpenTelemetryApi
import TerraSystemProfiler

/// Aggregates telemetry attributes from multiple profiler results.
///
/// Open for extension without modification — any new profiler just needs
/// `TelemetryAttributeConvertible` conformance to participate.
public struct ModelStatsSnapshot: Sendable, TelemetryAttributeConvertible {
  private let providers: [any TelemetryAttributeConvertible]

  public var telemetryAttributes: [String: AttributeValue] {
    providers.reduce(into: [:]) { result, provider in
      result.merge(provider.telemetryAttributes) { _, new in new }
    }
  }

  public init(_ providers: any TelemetryAttributeConvertible...) {
    self.providers = providers
  }

  public init(providers: [any TelemetryAttributeConvertible]) {
    self.providers = providers
  }
}
