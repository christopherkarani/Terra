import Foundation
import OpenTelemetryProtocolExporterCommon

public enum OTLPRequestDecoderError: Error, Sendable, Equatable, CustomStringConvertible {
  case unsupportedEncoding(String)
  case compressedSizeLimitExceeded(actual: Int, max: Int)
  case decompressedSizeLimitExceeded(max: Int)
  case invalidProtobuf(String)
  case malformedData(reason: String)
  case decompressionFailed(reason: String)

  public var description: String {
    switch self {
    case .unsupportedEncoding(let encoding):
      return "Unsupported content encoding: \(encoding)"
    case .compressedSizeLimitExceeded(let actual, let max):
      return "Compressed payload exceeds limit (\(actual) > \(max))"
    case .decompressedSizeLimitExceeded(let max):
      return "Decompressed payload exceeds limit (max: \(max))"
    case .invalidProtobuf(let reason):
      return "Invalid OTLP protobuf: \(reason)"
    case .malformedData(let reason):
      return "Malformed OTLP data: \(reason)"
    case .decompressionFailed(let reason):
      return "Decompression failed: \(reason)"
    }
  }
}

public struct OTLPRequestDecoder: Sendable {
  public struct Limits: Sendable, Hashable {
    public var maxBodyBytes: Int
    public var maxDecompressedBytes: Int

    public init(maxBodyBytes: Int, maxDecompressedBytes: Int) {
      self.maxBodyBytes = maxBodyBytes
      self.maxDecompressedBytes = maxDecompressedBytes
    }

    public static let `default` = Limits(
      maxBodyBytes: 10 * 1024 * 1024,
      maxDecompressedBytes: 50 * 1024 * 1024
    )
  }

  public let limits: Limits

  public init(limits: Limits = .default) {
    self.limits = limits
  }

  public init(maxBodyBytes: Int, maxDecompressedBytes: Int) {
    self.limits = Limits(maxBodyBytes: maxBodyBytes, maxDecompressedBytes: maxDecompressedBytes)
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

    for resourceSpans in request.resourceSpans {
      let resourceAttributesDict = attributesDictionary(from: resourceSpans.resource.attributes)
      let resourceAttributes = Attributes(dictionary: resourceAttributesDict)
      let resource = Resource(attributes: resourceAttributes)

      for scopeSpans in resourceSpans.scopeSpans {
        for span in scopeSpans.spans {
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

    var attributesDict = attributesDictionary(from: span.attributes)

    if let serviceName = resourceAttributes["service.name"] {
      attributesDict["service.name"] = serviceName
    }

    for (key, value) in resourceAttributes
    where key.hasPrefix("gen_ai.") || key.hasPrefix("terra.") {
      if attributesDict[key] == nil {
        attributesDict[key] = value
      }
    }

    attributesDict["span.kind"] = .string(kind.rawValue)
    attributesDict["status.code"] = .string(status.rawValue)

    let attributes = Attributes(dictionary: attributesDict)

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
      resource: resource
    )
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
    from keyValues: [Opentelemetry_Proto_Common_V1_KeyValue]
  ) -> [String: AttributeValue] {
    var result: [String: AttributeValue] = [:]
    result.reserveCapacity(keyValues.count)

    for keyValue in keyValues {
      let key = keyValue.key
      guard !key.isEmpty else { continue }
      result[key] = attributeValue(from: keyValue.value)
    }

    return result
  }

  private func attributeValue(
    from value: Opentelemetry_Proto_Common_V1_AnyValue
  ) -> AttributeValue {
    switch value.value {
    case .stringValue(let string):
      return .string(string)
    case .boolValue(let bool):
      return .bool(bool)
    case .intValue(let int):
      return .int(int)
    case .doubleValue(let double):
      return .double(double)
    case .arrayValue(let array):
      return .array(array.values.map { attributeValue(from: $0) })
    case .kvlistValue(let kvlist):
      let attributes = kvlist.values.map { Attribute(key: $0.key, value: attributeValue(from: $0.value)) }
      return .kvlist(attributes)
    case .bytesValue(let data):
      return .bytes(Array(data))
    case .none:
      return .null
    }
  }
}
