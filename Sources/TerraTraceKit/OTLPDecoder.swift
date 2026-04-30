import Foundation

#if canImport(OpenTelemetryProtocolExporterCommon)
  import OpenTelemetryProtocolExporterCommon
#elseif canImport(OpenTelemetryProtocolExporterGrpc)
  import OpenTelemetryProtocolExporterGrpc
#elseif canImport(OpenTelemetryProtocolExporterHttp)
  import OpenTelemetryProtocolExporterHttp
#elseif canImport(OpenTelemetryProtocolExporterHTTP)
  import OpenTelemetryProtocolExporterHTTP
#endif

public enum OTLPRequestDecoderError: Error, Sendable, Equatable, CustomStringConvertible {
  case unsupportedEncoding(String)
  case compressedSizeLimitExceeded(actual: Int, max: Int)
  case decompressedSizeLimitExceeded(max: Int)
  case invalidProtobuf(String)
  case malformedData(reason: String)
  case decompressionFailed(reason: String)

  public var description: String {
    switch self {
    case let .unsupportedEncoding(encoding):
      return "Unsupported content encoding: \(encoding)"
    case let .compressedSizeLimitExceeded(actual, max):
      return "Compressed payload exceeds limit (\(actual) > \(max))"
    case let .decompressedSizeLimitExceeded(max):
      return "Decompressed payload exceeds limit (max: \(max))"
    case let .invalidProtobuf(reason):
      return "Invalid OTLP protobuf: \(reason)"
    case let .malformedData(reason):
      return "Malformed OTLP data: \(reason)"
    case let .decompressionFailed(reason):
      return "Decompression failed: \(reason)"
    }
  }
}

public struct OTLPRequestDecoder: Sendable {
  public struct Limits: Sendable, Hashable {
    public var maxBodyBytes: Int
    public var maxDecompressedBytes: Int
    public var maxSpansPerRequest: Int
    public var maxAttributesPerSpan: Int
    public var maxAttributesPerResource: Int
    public var maxEventsPerSpan: Int
    public var maxLinksPerSpan: Int
    public var maxAttributesPerEvent: Int
    public var maxAttributesPerLink: Int
    public var maxAttributeKeyBytes: Int
    public var maxAttributeValueBytes: Int
    public var maxAnyValueDepth: Int

    public init(
      maxBodyBytes: Int,
      maxDecompressedBytes: Int,
      maxSpansPerRequest: Int = 10000,
      maxAttributesPerSpan: Int = 256,
      maxAttributesPerResource: Int = 256,
      maxEventsPerSpan: Int = 1024,
      maxLinksPerSpan: Int = 128,
      maxAttributesPerEvent: Int = 64,
      maxAttributesPerLink: Int = 64,
      maxAttributeKeyBytes: Int = 512,
      maxAttributeValueBytes: Int = 8 * 1024,
      maxAnyValueDepth: Int = 8
    ) {
      self.maxBodyBytes = maxBodyBytes
      self.maxDecompressedBytes = maxDecompressedBytes
      self.maxSpansPerRequest = maxSpansPerRequest
      self.maxAttributesPerSpan = maxAttributesPerSpan
      self.maxAttributesPerResource = maxAttributesPerResource
      self.maxEventsPerSpan = maxEventsPerSpan
      self.maxLinksPerSpan = maxLinksPerSpan
      self.maxAttributesPerEvent = maxAttributesPerEvent
      self.maxAttributesPerLink = maxAttributesPerLink
      self.maxAttributeKeyBytes = maxAttributeKeyBytes
      self.maxAttributeValueBytes = maxAttributeValueBytes
      self.maxAnyValueDepth = maxAnyValueDepth
    }

    public static let `default` = Limits(
      maxBodyBytes: 10 * 1024 * 1024,
      maxDecompressedBytes: 50 * 1024 * 1024,
      maxSpansPerRequest: 10000,
      maxAttributesPerSpan: 256,
      maxAttributesPerResource: 256,
      maxEventsPerSpan: 1024,
      maxLinksPerSpan: 128,
      maxAttributesPerEvent: 64,
      maxAttributesPerLink: 64,
      maxAttributeKeyBytes: 512,
      maxAttributeValueBytes: 8 * 1024,
      maxAnyValueDepth: 8
    )
  }

  public let limits: Limits

  public init(limits: Limits = .default) {
    self.limits = limits
  }

  public init(maxBodyBytes: Int, maxDecompressedBytes: Int) {
    limits = Limits(
      maxBodyBytes: maxBodyBytes,
      maxDecompressedBytes: maxDecompressedBytes
    )
  }

  public func decode(headers: [String: String], body: Data) throws -> [SpanRecord] {
    try decode(body: body, headers: headers)
  }

  public func decode(body: Data, headers: [String: String]) throws -> [SpanRecord] {
    guard body.count <= limits.maxBodyBytes else {
      throw OTLPRequestDecoderError.compressedSizeLimitExceeded(
        actual: body.count,
        max: limits.maxBodyBytes
      )
    }

    let encoding = try parseEncoding(from: headers)
    let payload = try OTLPDecompressor.decompress(
      body,
      encoding: encoding,
      maxOutputBytes: limits.maxDecompressedBytes
    )

    let request: Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest
    do {
      request = try Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest(
        serializedData: payload
      )
    } catch {
      throw OTLPRequestDecoderError.invalidProtobuf(error.localizedDescription)
    }

    return try mapRequest(request)
  }

  private func parseEncoding(from headers: [String: String]) throws -> OTLPContentEncoding {
    guard let raw = headerValue("content-encoding", in: headers), !raw.isEmpty else {
      return .identity
    }

    let normalized = raw
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    guard normalized.count == 1, let encoding = normalized.first else {
      throw OTLPRequestDecoderError.unsupportedEncoding(raw)
    }

    switch encoding {
    case "gzip", "x-gzip":
      return .gzip
    case "deflate":
      return .deflate
    case "identity":
      return .identity
    default:
      throw OTLPRequestDecoderError.unsupportedEncoding(encoding)
    }
  }

  private func headerValue(_ name: String, in headers: [String: String]) -> String? {
    if let value = headers[name] { return value }
    let lowercased = name.lowercased()
    for (key, value) in headers where key.lowercased() == lowercased {
      return value
    }
    return nil
  }

  private func mapRequest(
    _ request: Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest
  ) throws -> [SpanRecord] {
    var records: [SpanRecord] = []
    let estimatedCount = request.resourceSpans.reduce(0) { sum, rs in
      sum + rs.scopeSpans.reduce(0) { $0 + $1.spans.count }
    }
    guard estimatedCount <= limits.maxSpansPerRequest else {
      throw OTLPRequestDecoderError.malformedData(
        reason: "Span count \(estimatedCount) exceeds limit \(limits.maxSpansPerRequest)"
      )
    }
    records.reserveCapacity(estimatedCount)

    var seenSpanCount = 0
    for resourceSpans in request.resourceSpans {
      guard resourceSpans.resource.attributes.count <= limits.maxAttributesPerResource else {
        throw OTLPRequestDecoderError.malformedData(
          reason: "Resource has \(resourceSpans.resource.attributes.count) attributes (limit \(limits.maxAttributesPerResource))"
        )
      }
      let resourceAttributesDict = try attributesDictionary(
        from: resourceSpans.resource.attributes,
        limit: limits.maxAttributesPerResource,
        owner: "resource"
      )
      let resourceAttributes = Attributes(dictionary: resourceAttributesDict)
      let resource = Resource(attributes: resourceAttributes)

      for scopeSpans in resourceSpans.scopeSpans {
        for span in scopeSpans.spans {
          seenSpanCount += 1
          guard seenSpanCount <= limits.maxSpansPerRequest else {
            throw OTLPRequestDecoderError.malformedData(
              reason: "Span count \(seenSpanCount) exceeds limit \(limits.maxSpansPerRequest)"
            )
          }
          let record = try mapSpan(
            span,
            resource: resource,
            resourceAttributes: resourceAttributesDict
          )
          records.append(record)
        }
      }
    }

    return records
  }

  private func mapSpan(
    _ span: Opentelemetry_Proto_Trace_V1_Span,
    resource: Resource,
    resourceAttributes: [String: AttributeValue]
  ) throws -> SpanRecord {
    guard let traceID = TraceID(data: span.traceID) else {
      throw OTLPRequestDecoderError.malformedData(reason: "Invalid trace_id length")
    }

    guard let spanID = SpanID(data: span.spanID) else {
      throw OTLPRequestDecoderError.malformedData(reason: "Invalid span_id length")
    }

    let parentSpanID: SpanID?
    if span.parentSpanID.isEmpty {
      parentSpanID = nil
    } else {
      guard let parsed = SpanID(data: span.parentSpanID) else {
        throw OTLPRequestDecoderError.malformedData(reason: "Invalid parent_span_id length")
      }
      parentSpanID = parsed
    }

    let kind = mapSpanKind(span.kind.rawValue)
    let status = mapStatusCode(span.status.code.rawValue)
    let statusDescription = span.status.message.isEmpty ? nil : span.status.message

    guard span.attributes.count <= limits.maxAttributesPerSpan else {
      throw OTLPRequestDecoderError.malformedData(
        reason: "Span '\(span.name)' has \(span.attributes.count) attributes (limit \(limits.maxAttributesPerSpan))"
      )
    }
    guard span.events.count <= limits.maxEventsPerSpan else {
      throw OTLPRequestDecoderError.malformedData(
        reason: "Span '\(span.name)' has \(span.events.count) events (limit \(limits.maxEventsPerSpan))"
      )
    }
    guard span.links.count <= limits.maxLinksPerSpan else {
      throw OTLPRequestDecoderError.malformedData(
        reason: "Span '\(span.name)' has \(span.links.count) links (limit \(limits.maxLinksPerSpan))"
      )
    }

    var attributesDict = try attributesDictionary(
      from: span.attributes,
      limit: limits.maxAttributesPerSpan,
      owner: "span '\(span.name)'"
    )

    if let serviceName = resourceAttributes["service.name"] {
      attributesDict["service.name"] = serviceName
    }

    for (key, value) in resourceAttributes
      where key.hasPrefix("gen_ai.") || key.hasPrefix("terra.")
    {
      if attributesDict[key] == nil {
        attributesDict[key] = value
      }
    }

    attributesDict["span.kind"] = .string(kind.rawValue)
    attributesDict["status.code"] = .string(status.rawValue)

    let attributes = Attributes(dictionary: attributesDict)
    let events = try mapEvents(span.events, spanName: span.name)
    let links = try mapLinks(span.links, spanName: span.name)

    return SpanRecord(
      traceID: traceID,
      spanID: spanID,
      parentSpanID: parentSpanID,
      name: span.name,
      kind: kind,
      status: status,
      startTimeUnixNano: span.startTimeUnixNano,
      endTimeUnixNano: span.endTimeUnixNano,
      attributes: attributes,
      resource: resource,
      statusDescription: statusDescription,
      events: events,
      links: links,
      droppedAttributesCount: span.droppedAttributesCount,
      droppedEventsCount: span.droppedEventsCount,
      droppedLinksCount: span.droppedLinksCount
    )
  }

  private func mapEvents(
    _ events: [Opentelemetry_Proto_Trace_V1_Span.Event],
    spanName: String
  ) throws -> [SpanEventRecord] {
    try events.map { event in
      guard event.attributes.count <= limits.maxAttributesPerEvent else {
        throw OTLPRequestDecoderError.malformedData(
          reason: "Event '\(event.name)' on span '\(spanName)' has \(event.attributes.count) attributes (limit \(limits.maxAttributesPerEvent))"
        )
      }
      let attributes = try attributesDictionary(
        from: event.attributes,
        limit: limits.maxAttributesPerEvent,
        owner: "event '\(event.name)'"
      )
      return SpanEventRecord(
        name: event.name,
        timeUnixNano: event.timeUnixNano,
        attributes: Attributes(dictionary: attributes),
        droppedAttributesCount: event.droppedAttributesCount
      )
    }
  }

  private func mapLinks(
    _ links: [Opentelemetry_Proto_Trace_V1_Span.Link],
    spanName: String
  ) throws -> [SpanLinkRecord] {
    try links.map { link in
      guard let traceID = TraceID(data: link.traceID) else {
        throw OTLPRequestDecoderError.malformedData(reason: "Invalid link trace_id length on span '\(spanName)'")
      }
      guard let spanID = SpanID(data: link.spanID) else {
        throw OTLPRequestDecoderError.malformedData(reason: "Invalid link span_id length on span '\(spanName)'")
      }
      guard link.attributes.count <= limits.maxAttributesPerLink else {
        throw OTLPRequestDecoderError.malformedData(
          reason: "Link on span '\(spanName)' has \(link.attributes.count) attributes (limit \(limits.maxAttributesPerLink))"
        )
      }
      let attributes = try attributesDictionary(
        from: link.attributes,
        limit: limits.maxAttributesPerLink,
        owner: "link on span '\(spanName)'"
      )
      return SpanLinkRecord(
        traceID: traceID,
        spanID: spanID,
        traceState: link.traceState,
        attributes: Attributes(dictionary: attributes),
        droppedAttributesCount: link.droppedAttributesCount
      )
    }
  }

  private func mapSpanKind(_ rawValue: Int) -> SpanKind {
    switch rawValue {
    case 1:
      return .internal
    case 2:
      return .server
    case 3:
      return .client
    case 4:
      return .producer
    case 5:
      return .consumer
    default:
      return .unspecified
    }
  }

  private func mapStatusCode(_ rawValue: Int) -> StatusCode {
    switch rawValue {
    case 1:
      return .ok
    case 2:
      return .error
    default:
      return .unset
    }
  }

  private func attributesDictionary(
    from keyValues: [Opentelemetry_Proto_Common_V1_KeyValue],
    limit: Int,
    owner: String
  ) throws -> [String: AttributeValue] {
    guard keyValues.count <= limit else {
      throw OTLPRequestDecoderError.malformedData(
        reason: "\(owner) has \(keyValues.count) attributes (limit \(limit))"
      )
    }

    var result: [String: AttributeValue] = [:]
    result.reserveCapacity(keyValues.count)

    for keyValue in keyValues {
      let key = keyValue.key
      guard !key.isEmpty else { continue }
      guard key.utf8.count <= limits.maxAttributeKeyBytes else {
        throw OTLPRequestDecoderError.malformedData(
          reason: "\(owner) attribute key exceeds \(limits.maxAttributeKeyBytes) bytes"
        )
      }
      let value = try attributeValue(from: keyValue.value, depth: 0)
      guard attributeValueByteCount(value) <= limits.maxAttributeValueBytes else {
        throw OTLPRequestDecoderError.malformedData(
          reason: "\(owner) attribute '\(key)' value exceeds \(limits.maxAttributeValueBytes) bytes"
        )
      }
      result[key] = value
    }

    return result
  }

  private func attributeValue(
    from value: Opentelemetry_Proto_Common_V1_AnyValue,
    depth: Int
  ) throws -> AttributeValue {
    guard depth <= limits.maxAnyValueDepth else {
      throw OTLPRequestDecoderError.malformedData(
        reason: "AnyValue nesting depth exceeded limit \(limits.maxAnyValueDepth)"
      )
    }

    switch value.value {
    case let .stringValue(string):
      return .string(string)
    case let .boolValue(bool):
      return .bool(bool)
    case let .intValue(int):
      return .int(int)
    case let .doubleValue(double):
      return .double(double)
    case let .arrayValue(array):
      let values = try array.values.map { try attributeValue(from: $0, depth: depth + 1) }
      return .array(values)
    case let .kvlistValue(kvlist):
      let attributes = try kvlist.values.map {
        try Attribute(key: $0.key, value: attributeValue(from: $0.value, depth: depth + 1))
      }
      return .kvlist(attributes)
    case let .bytesValue(data):
      return .bytes(Array(data))
    case .none:
      return .null
    }
  }

  private func attributeValueByteCount(_ value: AttributeValue) -> Int {
    switch value {
    case let .string(string):
      return string.utf8.count
    case .bool:
      return 1
    case .int, .double:
      return 8
    case let .bytes(bytes):
      return bytes.count
    case let .array(values):
      return values.reduce(0) { $0 + attributeValueByteCount($1) }
    case let .kvlist(attributes):
      return attributes.reduce(0) { partial, attribute in
        partial + attribute.key.utf8.count + attributeValueByteCount(attribute.value)
      }
    case .null:
      return 0
    }
  }
}
