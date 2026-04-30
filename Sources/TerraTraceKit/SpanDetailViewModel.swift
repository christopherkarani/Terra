import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

/// Display-ready attribute entry.
struct AttributeItem: Hashable, Identifiable {
  var id: String { "\(key)=\(value)" }
  let key: String
  let value: String
}

/// Display-ready event entry.
struct EventItem: Hashable, Identifiable {
  let id: String
  let name: String
  let timestamp: Date
  let attributes: [(String, String)]
  let attributesText: String

  init(name: String, timestamp: Date, attributes: [(String, String)] = []) {
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

  static func == (lhs: EventItem, rhs: EventItem) -> Bool {
    lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

/// Display-ready link entry. Attributes are routed through the privacy
/// predicate at construction so any future surface that renders them inherits
/// the same redaction guarantees as span attributes.
struct LinkItem: Hashable, Identifiable {
  var id: String { "\(traceId.hexString)-\(spanId.hexString)" }
  let traceId: TraceId
  let spanId: SpanId
  let attributes: [(String, String)]

  init(traceId: TraceId, spanId: SpanId, attributes: [(String, String)] = []) {
    self.traceId = traceId
    self.spanId = spanId
    self.attributes = attributes
  }

  static func == (lhs: LinkItem, rhs: LinkItem) -> Bool {
    lhs.traceId == rhs.traceId
      && lhs.spanId == rhs.spanId
      && lhs.attributes.elementsEqual(rhs.attributes, by: ==)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(traceId)
    hasher.combine(spanId)
    for pair in attributes {
      hasher.combine(pair.0)
      hasher.combine(pair.1)
    }
  }
}

/// View model for a selected span's details.
@MainActor
final class SpanDetailViewModel {
  /// Currently selected span.
  private(set) var selectedSpan: SpanData?
  /// Attributes prepared for display.
  private(set) var attributeItems: [AttributeItem] = []
  /// Privacy-aware status description for the selected span, when present.
  /// `nil` when the underlying status carries no message.
  private(set) var displayedStatusDescription: String?
  /// Events prepared for display.
  private(set) var eventItems: [EventItem] = []
  /// Recommendation events prepared for display.
  private(set) var recommendationEventItems: [EventItem] = []
  /// Anomaly events prepared for display.
  private(set) var anomalyEventItems: [EventItem] = []
  /// Policy and audit events prepared for display.
  private(set) var policyEventItems: [EventItem] = []
  /// Hardware telemetry events prepared for display.
  private(set) var hardwareEventItems: [EventItem] = []
  /// Stream lifecycle events prepared for display.
  private(set) var lifecycleEventItems: [EventItem] = []
  /// Links prepared for display.
  private(set) var linkItems: [LinkItem] = []

  /// Event counts by category for display as filter chips.
  var eventCategoryCounts: [String: Int] {
    [
      "Lifecycle": lifecycleEventItems.count,
      "Policy": policyEventItems.count,
      "Recommendations": recommendationEventItems.count,
      "Anomalies": anomalyEventItems.count,
      "Hardware": hardwareEventItems.count,
    ]
  }

  /// Creates an empty detail view model.
  init() {}

  /// Updates detail state for the selected span.
  func select(span: SpanData) {
    selectedSpan = span
    attributeItems = span.attributes
      .sorted(by: { $0.key < $1.key })
      .map {
        AttributeItem(
          key: $0.key,
          value: TelemetryPrivacy.displayValue(forKey: $0.key, value: $0.value.description)
        )
      }
    displayedStatusDescription = redactedStatusDescription(for: span.status)

    let allEvents = span.events.sorted(by: { $0.timestamp < $1.timestamp })
    let preparedEvents = allEvents.map { event in
      (
        source: event,
        item: EventItem(
          name: redactedEventName(event.name),
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
      LinkItem(
        traceId: link.context.traceId,
        spanId: link.context.spanId,
        attributes: normalizedAttributes(link.attributes)
      )
    }
  }

  /// Clears the current selection and associated detail state.
  func clearSelection() {
    selectedSpan = nil
    attributeItems = []
    displayedStatusDescription = nil
    eventItems = []
    recommendationEventItems = []
    anomalyEventItems = []
    policyEventItems = []
    hardwareEventItems = []
    lifecycleEventItems = []
    linkItems = []
  }

  // MARK: - Privacy-aware projections

  private func redactedStatusDescription(for status: Status) -> String? {
    guard case let .error(description) = status else { return nil }
    let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return TelemetryPrivacy.shouldRedactStatusDescription(trimmed)
      ? TelemetryPrivacy.redactedValue
      : trimmed
  }

  private func redactedEventName(_ name: String) -> String {
    TelemetryPrivacy.shouldRedactEventName(name) ? TelemetryPrivacy.redactedValue : name
  }

  private func normalizedAttributes(_ values: [String: OpenTelemetryApi.AttributeValue]) -> [(String, String)] {
    values.map { key, value in
      (key, TelemetryPrivacy.displayValue(forKey: key, value: value.description))
    }.sorted { lhs, rhs in
      lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
    }
  }
}
