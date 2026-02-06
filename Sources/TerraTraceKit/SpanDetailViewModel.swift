import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

/// Display-ready attribute entry.
public struct AttributeItem: Hashable {
  public let key: String
  public let value: String
}

/// Display-ready event entry.
public struct EventItem: Hashable {
  public let name: String
  public let timestamp: Date
}

/// Display-ready link entry.
public struct LinkItem: Hashable {
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

    eventItems = span.events
      .sorted(by: { $0.timestamp < $1.timestamp })
      .map { EventItem(name: $0.name, timestamp: $0.timestamp) }

    linkItems = span.links.map { link in
      LinkItem(traceId: link.context.traceId, spanId: link.context.spanId)
    }
  }

  /// Clears the current selection and associated detail state.
  public func clearSelection() {
    selectedSpan = nil
    attributeItems = []
    eventItems = []
    linkItems = []
  }
}
