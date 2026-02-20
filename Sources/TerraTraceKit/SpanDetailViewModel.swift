import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

/// Display-ready attribute entry.
public struct AttributeItem: Hashable, Identifiable {
  public var id: String { key }
  public let key: String
  public let value: String
}

/// Display-ready event entry.
public struct EventItem: Hashable, Identifiable {
  public let id: String
  public let name: String
  public let timestamp: Date
  public let attributes: [(String, String)]
  public let attributesText: String

  public init(name: String, timestamp: Date, attributes: [(String, String)] = []) {
    self.name = name
    self.timestamp = timestamp
    self.attributes = attributes

    attributesText = attributes
      .map { "\($0.0)=\($0.1)" }
      .joined(separator: "; ")

    let compact = attributesText
      .replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: ";", with: "_")
    id = "\(name)|\(timestamp.timeIntervalSinceReferenceDate)|\(compact)"
  }

  public static func == (lhs: EventItem, rhs: EventItem) -> Bool {
    lhs.id == rhs.id
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

/// Display-ready link entry.
public struct LinkItem: Hashable, Identifiable {
  public var id: String { "\(traceId.hexString)-\(spanId.hexString)" }
  public let traceId: TraceId
  public let spanId: SpanId
}

/// View model for a selected span's details.
public final class SpanDetailViewModel {
  /// Currently selected span.
  public private(set) var selectedSpan: SpanData?
  /// Attributes prepared for display.
  public private(set) var attributeItems: [AttributeItem] = []
  /// Events prepared for display.
  public private(set) var eventItems: [EventItem] = []
  /// Recommendation events prepared for display.
  public private(set) var recommendationEventItems: [EventItem] = []
  /// Anomaly events prepared for display.
  public private(set) var anomalyEventItems: [EventItem] = []
  /// Hardware telemetry events prepared for display.
  public private(set) var hardwareEventItems: [EventItem] = []
  /// Links prepared for display.
  public private(set) var linkItems: [LinkItem] = []

  /// Creates an empty detail view model.
  public init() {}

  /// Updates detail state for the selected span.
  public func select(span: SpanData) {
    selectedSpan = span
    attributeItems = span.attributes
      .sorted(by: { $0.key < $1.key })
      .map { AttributeItem(key: $0.key, value: $0.value.description) }

    let allEvents = span.events
      .sorted(by: { $0.timestamp < $1.timestamp })
      .map { event in
        EventItem(
          name: event.name,
          timestamp: event.timestamp,
          attributes: normalizedAttributes(event.attributes)
        )
      }

    eventItems = allEvents
    recommendationEventItems = allEvents.filter {
      isRecommendationEvent(name: $0.name, attributes: $0.attributes)
    }
    anomalyEventItems = allEvents.filter {
      isAnomalyEvent(name: $0.name, attributes: $0.attributes)
    }
    hardwareEventItems = allEvents.filter {
      isHardwareEvent(name: $0.name, attributes: $0.attributes)
    }

    linkItems = span.links.map { link in
      LinkItem(traceId: link.context.traceId, spanId: link.context.spanId)
    }
  }

  /// Clears the current selection and associated detail state.
  public func clearSelection() {
    selectedSpan = nil
    attributeItems = []
    eventItems = []
    recommendationEventItems = []
    anomalyEventItems = []
    hardwareEventItems = []
    linkItems = []
  }

  private func isRecommendationEvent(name: String, attributes: [(String, String)]) -> Bool {
    if name == TerraTelemetryKey.recommendationEventName {
      return true
    }
    return attributes.contains {
      $0.0.hasPrefix(TerraTelemetryKey.recommendationAttributePrefix)
    }
  }

  private func isAnomalyEvent(name: String, attributes: [(String, String)]) -> Bool {
    if name.hasPrefix(TerraTelemetryKey.anomalyNamePrefix) {
      return true
    }
    return attributes.contains {
      $0.0.hasPrefix(TerraTelemetryKey.anomalyAttributePrefix)
    }
  }

  private func isHardwareEvent(name: String, attributes: [(String, String)]) -> Bool {
    if name.hasPrefix(TerraTelemetryKey.hardwareNamePrefix) {
      return true
    }
    return attributes.contains {
      TerraTelemetryKey.hardwareAttributeKeys.contains($0.0)
    }
  }

  private func normalizedAttributes(_ values: [String: OpenTelemetryApi.AttributeValue]) -> [(String, String)] {
    values.map { key, value in
      (key, value.description)
    }.sorted { lhs, rhs in
      lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
    }
  }
}

private enum TerraTelemetryKey {
  static let recommendationEventName = "terra.recommendation"
  static let recommendationAttributePrefix = "terra.recommendation."
  static let anomalyNamePrefix = "terra.anomaly"
  static let anomalyAttributePrefix = "terra.anomaly."
  static let hardwareNamePrefix = "terra.process."
  static let hardwareAttributeKeys: Set<String> = [
    "terra.process.thermal_state",
    "terra.process.memory_resident_delta_mb",
    "terra.process.memory_peak_mb",
    "terra.hw.power_state",
    "terra.hw.memory_pressure",
    "terra.hw.rss_mb",
    "terra.hw.memory_churn_mb",
    "terra.hw.gpu_occupancy_pct",
    "terra.hw.ane_utilization_pct",
  ]
}
