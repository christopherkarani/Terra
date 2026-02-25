import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

/// Display-ready attribute entry.
public struct AttributeItem: Hashable, Identifiable {
  public var id: String { "\(key)=\(value)" }
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
@MainActor
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
  /// Policy and audit events prepared for display.
  public private(set) var policyEventItems: [EventItem] = []
  /// Hardware telemetry events prepared for display.
  public private(set) var hardwareEventItems: [EventItem] = []
  /// Stream lifecycle events prepared for display.
  public private(set) var lifecycleEventItems: [EventItem] = []
  /// Links prepared for display.
  public private(set) var linkItems: [LinkItem] = []

  /// Event counts by category for display as filter chips.
  public var eventCategoryCounts: [String: Int] {
    [
      "Lifecycle": lifecycleEventItems.count,
      "Policy": policyEventItems.count,
      "Recommendations": recommendationEventItems.count,
      "Anomalies": anomalyEventItems.count,
      "Hardware": hardwareEventItems.count,
    ]
  }

  /// Creates an empty detail view model.
  public init() {}

  /// Updates detail state for the selected span.
  public func select(span: SpanData) {
    selectedSpan = span
    attributeItems = span.attributes
      .sorted(by: { $0.key < $1.key })
      .map { AttributeItem(key: $0.key, value: $0.value.description) }

    let allEvents = span.events.sorted(by: { $0.timestamp < $1.timestamp })
    let preparedEvents = allEvents.map { event in
      (
        source: event,
        item: EventItem(
          name: event.name,
          timestamp: event.timestamp,
          attributes: normalizedAttributes(event.attributes)
        )
      )
    }

    // Single-pass classification instead of 6 iterations
    var allItems = [EventItem]()
    var recommendations = [EventItem]()
    var anomalies = [EventItem]()
    var policy = [EventItem]()
    var hardware = [EventItem]()
    var lifecycle = [EventItem]()

    for entry in preparedEvents {
      allItems.append(entry.item)
      let name = entry.source.name
      let attrs = entry.source.attributes
      if TerraTelemetryClassifier.isRecommendationEvent(name: name, attributes: attrs) {
        recommendations.append(entry.item)
      }
      if TerraTelemetryClassifier.isAnomalyEvent(name: name, attributes: attrs) {
        anomalies.append(entry.item)
      }
      if TerraTelemetryClassifier.isPolicyEvent(name: name, attributes: attrs) {
        policy.append(entry.item)
      }
      if TerraTelemetryClassifier.isHardwareEvent(name: name, attributes: attrs) {
        hardware.append(entry.item)
      }
      if TerraTelemetryClassifier.isLifecycleEvent(name: name, attributes: attrs) {
        lifecycle.append(entry.item)
      }
    }

    eventItems = allItems
    recommendationEventItems = recommendations
    anomalyEventItems = anomalies
    policyEventItems = policy
    hardwareEventItems = hardware
    lifecycleEventItems = lifecycle

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
    policyEventItems = []
    hardwareEventItems = []
    lifecycleEventItems = []
    linkItems = []
  }

  private func normalizedAttributes(_ values: [String: OpenTelemetryApi.AttributeValue]) -> [(String, String)] {
    values.map { key, value in
      (key, value.description)
    }.sorted { lhs, rhs in
      lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
    }
  }
}
