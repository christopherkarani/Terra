import Foundation

public struct TraceID: Hashable, Sendable, Comparable, CustomStringConvertible {
  public let bytes: [UInt8]

  public init?(data: Data) {
    guard data.count == 16 else { return nil }
    bytes = Array(data)
  }

  public init?(hex: String) {
    let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    guard cleaned.count == 32 else { return nil }
    var parsed: [UInt8] = []
    parsed.reserveCapacity(16)
    var index = cleaned.startIndex
    while index < cleaned.endIndex {
      let nextIndex = cleaned.index(index, offsetBy: 2)
      let byteString = cleaned[index..<nextIndex]
      guard let byte = UInt8(byteString, radix: 16) else { return nil }
      parsed.append(byte)
      index = nextIndex
    }
    bytes = parsed
  }

  public init?(bytes: [UInt8]) {
    guard bytes.count == 16 else { return nil }
    self.bytes = bytes
  }

  public var hex: String {
    bytes.map { String(format: "%02x", $0) }.joined()
  }

  public var short: String {
    let full = hex
    return full.count > 8 ? String(full.suffix(8)) : full
  }

  public var description: String { hex }

  public static func < (lhs: TraceID, rhs: TraceID) -> Bool {
    lhs.bytes.lexicographicallyPrecedes(rhs.bytes)
  }
}

public struct SpanID: Hashable, Sendable, Comparable, CustomStringConvertible {
  public let bytes: [UInt8]

  public init?(data: Data) {
    guard data.count == 8 else { return nil }
    bytes = Array(data)
  }

  public init?(hex: String) {
    let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    guard cleaned.count == 16 else { return nil }
    var parsed: [UInt8] = []
    parsed.reserveCapacity(8)
    var index = cleaned.startIndex
    while index < cleaned.endIndex {
      let nextIndex = cleaned.index(index, offsetBy: 2)
      let byteString = cleaned[index..<nextIndex]
      guard let byte = UInt8(byteString, radix: 16) else { return nil }
      parsed.append(byte)
      index = nextIndex
    }
    bytes = parsed
  }

  public init?(bytes: [UInt8]) {
    guard bytes.count == 8 else { return nil }
    self.bytes = bytes
  }

  public var hex: String {
    bytes.map { String(format: "%02x", $0) }.joined()
  }

  public var short: String {
    let full = hex
    return full.count > 8 ? String(full.suffix(8)) : full
  }

  public var description: String { hex }

  public static func < (lhs: SpanID, rhs: SpanID) -> Bool {
    lhs.bytes.lexicographicallyPrecedes(rhs.bytes)
  }
}

public enum SpanKind: String, Sendable, Hashable {
  case unspecified
  case `internal` = "internal"
  case server
  case client
  case producer
  case consumer
}

public enum StatusCode: String, Sendable, Hashable {
  case unset
  case ok
  case error
}

public enum AttributeValue: Hashable, Sendable {
  case string(String)
  case bool(Bool)
  case int(Int64)
  case double(Double)
  case bytes([UInt8])
  case array([AttributeValue])
  case kvlist([Attribute])
  case null

  public var stringValue: String? {
    if case .string(let value) = self {
      return value
    }
    return nil
  }

  public var boolValue: Bool? {
    if case .bool(let value) = self {
      return value
    }
    return nil
  }

  public var intValue: Int64? {
    if case .int(let value) = self {
      return value
    }
    return nil
  }

  public var doubleValue: Double? {
    if case .double(let value) = self {
      return value
    }
    return nil
  }

  public var isNull: Bool {
    if case .null = self {
      return true
    }
    return false
  }
}

extension AttributeValue: CustomStringConvertible {
  public var description: String {
    switch self {
    case .string(let value):
      return value
    case .bool(let value):
      return value ? "true" : "false"
    case .int(let value):
      return String(value)
    case .double(let value):
      return String(value)
    case .bytes(let value):
      return value.map { String(format: "%02x", $0) }.joined()
    case .array(let values):
      return "[" + values.map { $0.description }.joined(separator: ",") + "]"
    case .kvlist(let values):
      let rendered = values.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
      return "{\(rendered)}"
    case .null:
      return "null"
    }
  }
}

public struct Attribute: Hashable, Sendable {
  public let key: String
  public let value: AttributeValue

  public init(key: String, value: AttributeValue) {
    self.key = key
    self.value = value
  }
}

public struct Attributes: Hashable, Sendable, Sequence {
  public let items: [Attribute]

  public init(_ items: [Attribute]) {
    self.items = Attributes.sorted(items)
  }

  public init(dictionary: [String: AttributeValue]) {
    let items = dictionary.map { Attribute(key: $0.key, value: $0.value) }
    self.items = Attributes.sorted(items)
  }

  public subscript(key: String) -> AttributeValue? {
    items.first(where: { $0.key == key })?.value
  }

  public subscript(string key: String) -> String? {
    self[key]?.stringValue
  }

  public var byKey: [String: AttributeValue] {
    items.reduce(into: [:]) { $0[$1.key] = $1.value }
  }

  public func makeIterator() -> AnyIterator<(String, AttributeValue)> {
    var iterator = items.makeIterator()
    return AnyIterator {
      guard let next = iterator.next() else { return nil }
      return (next.key, next.value)
    }
  }

  private static func sorted(_ items: [Attribute]) -> [Attribute] {
    items.sorted { lhs, rhs in
      if lhs.key == rhs.key {
        return lhs.value.stableSortKey < rhs.value.stableSortKey
      }
      return lhs.key < rhs.key
    }
  }
}

public struct Resource: Hashable, Sendable {
  public let attributes: Attributes

  public init(attributes: Attributes) {
    self.attributes = attributes
  }
}

public struct SpanRecord: Hashable, Sendable {
  public let traceID: TraceID
  public let spanID: SpanID
  public let parentSpanID: SpanID?
  public let name: String
  public let kind: SpanKind
  public let status: StatusCode
  public let startTimeUnixNano: UInt64
  public let endTimeUnixNano: UInt64
  public let attributes: Attributes
  public let resource: Resource
  public let events: [SpanRecordEvent]
  public let links: [SpanRecordLink]

  public init(
    traceID: TraceID,
    spanID: SpanID,
    parentSpanID: SpanID?,
    name: String,
    kind: SpanKind,
    status: StatusCode,
    startTimeUnixNano: UInt64,
    endTimeUnixNano: UInt64,
    attributes: Attributes,
    resource: Resource,
    events: [SpanRecordEvent] = [],
    links: [SpanRecordLink] = []
  ) {
    self.traceID = traceID
    self.spanID = spanID
    self.parentSpanID = parentSpanID
    self.name = name
    self.kind = kind
    self.status = status
    self.startTimeUnixNano = startTimeUnixNano
    self.endTimeUnixNano = endTimeUnixNano
    self.attributes = attributes
    self.resource = resource
    self.events = events
    self.links = links
  }

  public var durationNanoseconds: UInt64 {
    endTimeUnixNano >= startTimeUnixNano ? (endTimeUnixNano - startTimeUnixNano) : 0
  }

  public var resourceAttributes: Attributes {
    resource.attributes
  }
}

public struct SpanRecordEvent: Hashable, Sendable {
  public let name: String
  public let timestampUnixNano: UInt64
  public let attributes: Attributes

  public init(name: String, timestampUnixNano: UInt64, attributes: Attributes) {
    self.name = name
    self.timestampUnixNano = timestampUnixNano
    self.attributes = attributes
  }
}

public struct SpanRecordLink: Hashable, Sendable {
  public let traceID: TraceID
  public let spanID: SpanID
  public let attributes: Attributes

  public init(traceID: TraceID, spanID: SpanID, attributes: Attributes = Attributes([])) {
    self.traceID = traceID
    self.spanID = spanID
    self.attributes = attributes
  }
}

public struct TraceFilter: Hashable, Sendable {
  public var traceID: TraceID?
  public var namePrefix: String?

  public init(traceID: TraceID? = nil, namePrefix: String? = nil) {
    self.traceID = traceID
    self.namePrefix = namePrefix
  }

  public func matches(_ span: SpanRecord) -> Bool {
    if let traceID, traceID != span.traceID { return false }
    if let namePrefix, !span.name.hasPrefix(namePrefix) { return false }
    return true
  }
}

public struct TraceSnapshot: Sendable {
  public let allSpans: [SpanRecord]
  public let traces: [TraceID: [SpanRecord]]

  public init(allSpans: [SpanRecord], traces: [TraceID: [SpanRecord]]) {
    self.allSpans = allSpans
    self.traces = traces
  }
}

private extension AttributeValue {
  var stableSortKey: String {
    switch self {
    case .string(let value):
      return "s:\(value)"
    case .bool(let value):
      return "b:\(value)"
    case .int(let value):
      return "i:\(value)"
    case .double(let value):
      return "d:\(value)"
    case .bytes(let value):
      let hex = value.map { String(format: "%02x", $0) }.joined()
      return "x:\(hex)"
    case .array(let values):
      return "a:[" + values.map { $0.stableSortKey }.joined(separator: ",") + "]"
    case .kvlist(let values):
      return "k:[" + values.map { $0.key }.joined(separator: ",") + "]"
    case .null:
      return "n:"
    }
  }
}
