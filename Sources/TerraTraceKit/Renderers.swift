import Foundation

public struct StreamRenderer: Sendable {
  public let filter: TraceFilter?

  public init(filter: TraceFilter? = nil) {
    self.filter = filter
  }

  public func render(spans: [SpanRecord]) -> [String] {
    let filtered = spans.filter { spanMatchesFilter($0, filter: filter) }
    let ordered = filtered.sorted(by: spanStreamSort)

    return ordered.map { span in
      let timestamp = formatTimestamp(nanos: endTimeUnixNano(span))
      let duration = formatDuration(nanos: durationUnixNano(span))
      let traceShort = shortID(span.traceID)
      let spanShort = shortID(span.spanID)
      let attributes = renderAttributes(span)

      var parts: [String] = [timestamp, duration, span.name, traceShort, spanShort]
      parts.append(contentsOf: attributes)
      return parts.joined(separator: " ")
    }
  }
}

public struct TreeRenderer: Sendable {
  public let filter: TraceFilter?

  public init(filter: TraceFilter? = nil) {
    self.filter = filter
  }

  public func render(snapshot: TraceSnapshot) -> String {
    let filtered = snapshot.allSpans.filter { spanMatchesFilter($0, filter: filter) }
    guard !filtered.isEmpty else { return "" }

    let spansByTrace = Dictionary(grouping: filtered, by: { $0.traceID })
    let traceIDs = spansByTrace.keys.sorted()

    var lines: [String] = []
    for traceID in traceIDs {
      lines.append("trace \(shortID(traceID))")
      let traceSpans = spansByTrace[traceID] ?? []
      lines.append(contentsOf: renderTrace(spans: traceSpans))
    }

    return lines.joined(separator: "\n")
  }

  private func renderTrace(spans: [SpanRecord]) -> [String] {
    var spansByID: [SpanID: SpanRecord] = [:]
    spansByID.reserveCapacity(spans.count)

    for span in spans {
      spansByID[span.spanID] = span
    }

    var childrenByParent: [SpanID: [SpanRecord]] = [:]
    var roots: [SpanRecord] = []
    roots.reserveCapacity(spans.count)

    for span in spans {
      if let parentID = span.parentSpanID,
         parentID != span.spanID,
         spansByID[parentID] != nil {
        childrenByParent[parentID, default: []].append(span)
      } else {
        roots.append(span)
      }
    }

    let orderedRoots = roots.sorted(by: spanTreeSort)
    var lines: [String] = []
    lines.reserveCapacity(orderedRoots.count)

    for (index, root) in orderedRoots.enumerated() {
      let isLast = index == orderedRoots.count - 1
      lines.append(contentsOf: renderNode(root, prefix: "", isLast: isLast, childrenByParent: childrenByParent))
    }

    return lines
  }

  private func renderNode(
    _ span: SpanRecord,
    prefix: String,
    isLast: Bool,
    childrenByParent: [SpanID: [SpanRecord]]
  ) -> [String] {
    let branch = isLast ? "\\-- " : "|-- "
    let line = prefix + branch + treeLine(span)

    var lines: [String] = [line]

    let childPrefix = prefix + (isLast ? "    " : "|   ")
    let children = (childrenByParent[span.spanID] ?? []).sorted(by: spanTreeSort)

    for (index, child) in children.enumerated() {
      let childIsLast = index == children.count - 1
      lines.append(contentsOf: renderNode(child, prefix: childPrefix, isLast: childIsLast, childrenByParent: childrenByParent))
    }

    return lines
  }
}

private func treeLine(_ span: SpanRecord) -> String {
  let duration = formatDuration(nanos: durationUnixNano(span))
  let spanShort = shortID(span.spanID)
  let attributes = renderAttributes(span)

  var parts: [String] = [span.name, duration, spanShort]
  parts.append(contentsOf: attributes)
  return parts.joined(separator: " ")
}

private func spanStreamSort(_ lhs: SpanRecord, _ rhs: SpanRecord) -> Bool {
  let lhsEnd = endTimeUnixNano(lhs)
  let rhsEnd = endTimeUnixNano(rhs)
  if lhsEnd != rhsEnd { return lhsEnd < rhsEnd }

  if lhs.traceID != rhs.traceID { return lhs.traceID < rhs.traceID }
  if lhs.spanID != rhs.spanID { return lhs.spanID < rhs.spanID }

  return lhs.name < rhs.name
}

private func spanTreeSort(_ lhs: SpanRecord, _ rhs: SpanRecord) -> Bool {
  let lhsStart = startTimeUnixNano(lhs)
  let rhsStart = startTimeUnixNano(rhs)
  if lhsStart != rhsStart { return lhsStart < rhsStart }

  if lhs.spanID != rhs.spanID { return lhs.spanID < rhs.spanID }

  return lhs.name < rhs.name
}

private func spanMatchesFilter(_ span: SpanRecord, filter: TraceFilter?) -> Bool {
  filter?.matches(span) ?? true
}

private func renderAttributes(_ span: SpanRecord) -> [String] {
  let pairs = sortedAttributePairs(span.attributes)
  return pairs.map { "\($0)=\($1)" }
}

private func sortedAttributePairs(_ attributes: Attributes) -> [(String, String)] {
  // Attributes is already sorted on init — no need to re-sort
  attributes.items.map { ($0.key, String(describing: $0.value)) }
}

private func shortID<T>(_ id: T, length: Int = 8) -> String {
  let full = idString(id)
  guard full.count > length else { return full }
  return String(full.suffix(length))
}

private func idString<T>(_ id: T) -> String {
  String(describing: id)
}

private func startTimeUnixNano(_ span: SpanRecord) -> UInt64 {
  span.startTimeUnixNano
}

private func endTimeUnixNano(_ span: SpanRecord) -> UInt64 {
  span.endTimeUnixNano
}

private func durationUnixNano(_ span: SpanRecord) -> UInt64 {
  let start = startTimeUnixNano(span)
  let end = endTimeUnixNano(span)
  return end >= start ? (end - start) : 0
}

private func formatTimestamp(nanos: UInt64) -> String {
  guard nanos > 0 else { return "0" }
  let seconds = Double(nanos) / 1_000_000_000
  let date = Date(timeIntervalSince1970: seconds)
  return sharedTimestampFormatter.string(from: date)
}

private func formatDuration(nanos: UInt64) -> String {
  let ms = Double(nanos) / 1_000_000
  return String(format: "%.3fms", ms)
}

private let sharedTimestampFormatter: ISO8601DateFormatter = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  formatter.timeZone = TimeZone(secondsFromGMT: 0)
  return formatter
}()
