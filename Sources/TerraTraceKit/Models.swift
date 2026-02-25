import Foundation

public struct TraceID: Hashable, Sendable, Comparable, CustomStringConvertible {
  /// High 64-bit half of the 128-bit trace ID (big-endian byte order).
  public let hi: UInt64
  /// Low 64-bit half of the 128-bit trace ID (big-endian byte order).
  public let lo: UInt64

  public init?(data: Data) {
    guard data.count == 16 else { return nil }
    var hiValue: UInt64 = 0
    var loValue: UInt64 = 0
    _ = withUnsafeMutableBytes(of: &hiValue) { data.copyBytes(to: $0, from: 0..<8) }
    _ = withUnsafeMutableBytes(of: &loValue) { data.copyBytes(to: $0, from: 8..<16) }
    hi = UInt64(bigEndian: hiValue)
    lo = UInt64(bigEndian: loValue)
  }

  public init?(hex: String) {
    let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    guard cleaned.count == 32 else { return nil }
    let midIndex = cleaned.index(cleaned.startIndex, offsetBy: 16)
    let hiHex = String(cleaned[cleaned.startIndex..<midIndex])
    let loHex = String(cleaned[midIndex..<cleaned.endIndex])
    guard let hiValue = UInt64(hiHex, radix: 16),
          let loValue = UInt64(loHex, radix: 16) else { return nil }
    hi = hiValue
    lo = loValue
  }

  public init?(bytes: [UInt8]) {
    guard bytes.count == 16 else { return nil }
    self.init(data: Data(bytes))
  }

  /// Backward-compatible computed property that reconstructs [UInt8] from hi/lo.
  public var bytes: [UInt8] {
    var result = [UInt8](repeating: 0, count: 16)
    let hiBE = hi.bigEndian
    let loBE = lo.bigEndian
    withUnsafeBytes(of: hiBE) { buf in
      for i in 0..<8 { result[i] = buf[i] }
    }
    withUnsafeBytes(of: loBE) { buf in
      for i in 0..<8 { result[8 + i] = buf[i] }
    }
    return result
  }

  public var hex: String {
    String(format: "%016llx", hi) + String(format: "%016llx", lo)
  }

  public var short: String {
    let full = hex
    return full.count > 8 ? String(full.suffix(8)) : full
  }

  public var description: String { hex }

  public static func < (lhs: TraceID, rhs: TraceID) -> Bool {
    if lhs.hi != rhs.hi { return lhs.hi < rhs.hi }
    return lhs.lo < rhs.lo
  }
}

public struct SpanID: Hashable, Sendable, Comparable, CustomStringConvertible {
  /// The single 64-bit span ID (big-endian byte order).
  public let rawValue: UInt64

  public init?(data: Data) {
    guard data.count == 8 else { return nil }
    var value: UInt64 = 0
    _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: 0..<8) }
    rawValue = UInt64(bigEndian: value)
  }

  public init?(hex: String) {
    let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    guard cleaned.count == 16 else { return nil }
    guard let value = UInt64(cleaned, radix: 16) else { return nil }
    rawValue = value
  }

  public init?(bytes: [UInt8]) {
    guard bytes.count == 8 else { return nil }
    self.init(data: Data(bytes))
  }

  /// Backward-compatible computed property that reconstructs [UInt8] from rawValue.
  public var bytes: [UInt8] {
    var result = [UInt8](repeating: 0, count: 8)
    let be = rawValue.bigEndian
    withUnsafeBytes(of: be) { buf in
      for i in 0..<8 { result[i] = buf[i] }
    }
    return result
  }

  public var hex: String {
    String(format: "%016llx", rawValue)
  }

  public var short: String {
    let full = hex
    return full.count > 8 ? String(full.suffix(8)) : full
  }

  public var description: String { hex }

  public static func < (lhs: SpanID, rhs: SpanID) -> Bool {
    lhs.rawValue < rhs.rawValue
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
    // Binary search since items is always sorted by key
    var lo = items.startIndex
    var hi = items.endIndex
    while lo < hi {
      let mid = lo + (hi - lo) / 2
      if items[mid].key < key {
        lo = mid + 1
      } else if items[mid].key > key {
        hi = mid
      } else {
        return items[mid].value
      }
    }
    return nil
  }

  public subscript(string key: String) -> String? {
    self[key]?.stringValue
  }

  public var byKey: [String: AttributeValue] {
    items.reduce(into: [:]) { $0[$1.key] = $1.value }
  }

  public struct AttributesIterator: IteratorProtocol {
    var base: IndexingIterator<[Attribute]>
    public mutating func next() -> (String, AttributeValue)? {
      guard let attr = base.next() else { return nil }
      return (attr.key, attr.value)
    }
  }

  public func makeIterator() -> AttributesIterator {
    AttributesIterator(base: items.makeIterator())
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
    resource: Resource
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
  }

  public var durationNanoseconds: UInt64 {
    endTimeUnixNano >= startTimeUnixNano ? (endTimeUnixNano - startTimeUnixNano) : 0
  }

  public var resourceAttributes: Attributes {
    resource.attributes
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
