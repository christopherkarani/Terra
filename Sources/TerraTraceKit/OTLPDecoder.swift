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
  case unsupportedTerraSchema(version: String)
  case missingTerraSchemaAttributes([String])

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
    case .unsupportedTerraSchema(let version):
      return "Unsupported terra.semantic.version: \(version)"
    case .missingTerraSchemaAttributes(let attributes):
      return "Missing required terra schema attributes: \(attributes.joined(separator: ", "))"
    }
  }
}

public struct OTLPRequestDecoder: Sendable {
  private enum TerraContract {
    enum Keys {
      static let semanticVersion = "terra.semantic.version"
      static let schemaFamily = "terra.schema.family"
      static let runtime = "terra.runtime"
      static let requestID = "terra.request.id"
      static let sessionID = "terra.session.id"
      static let modelFingerprint = "terra.model.fingerprint"
    }

    static let requiredAttributeNames: Set<String> = [
      Keys.semanticVersion,
      Keys.schemaFamily,
      Keys.runtime,
      Keys.requestID,
      Keys.sessionID,
      Keys.modelFingerprint,
    ]

    static let supportedMajorVersion = "v1"
    static let requiredFamily = "terra"

    static func isSupportedSchemaVersion(_ version: String) -> Bool {
      let normalized = version.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard let major = parseMajorVersion(from: normalized) else { return false }
      return major == supportedMajorVersion
    }

    private static func parseMajorVersion(from version: String) -> String? {
      guard version.hasPrefix("v") else { return nil }
      let rest = String(version.dropFirst())
      guard let firstComponent = rest.split(separator: ".").first, let major = Int(firstComponent) else {
        return nil
      }
      return "v\(major)"
    }

  }

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
      let requestSpans = resourceSpans.scopeSpans.flatMap { $0.spans }
      try validateTerraContract(resourceAttributes: resourceAttributesDict, spans: requestSpans)

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

    let events = span.events.map {
      SpanRecordEvent(
        name: $0.name,
        timestampUnixNano: $0.timeUnixNano,
        attributes: Attributes(dictionary: attributesDictionary(from: $0.attributes))
      )
    }

    var links: [SpanRecordLink] = []
    links.reserveCapacity(span.links.count)
    for protoLink in span.links {
      guard
        let traceID = TraceID(data: protoLink.traceID),
        let spanID = SpanID(data: protoLink.spanID)
      else {
        continue
      }
      links.append(
        SpanRecordLink(
          traceID: traceID,
          spanID: spanID,
          attributes: Attributes(dictionary: attributesDictionary(from: protoLink.attributes))
        )
      )
    }

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
      events: events,
      links: links
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

  private func validateTerraContract(
    resourceAttributes: [String: AttributeValue],
    spans: [Opentelemetry_Proto_Trace_V1_Span]
  ) throws {
    let rootSpanAttributes = extractCandidateContractAttributes(
      from: spans,
      fallback: resourceAttributes
    )

    let missing = Self.TerraContract.requiredAttributeNames.subtracting(rootSpanAttributes.keys)
    if !missing.isEmpty {
      throw OTLPRequestDecoderError.missingTerraSchemaAttributes(Array(missing).sorted())
    }

    guard let version = stringValue(for: Self.TerraContract.Keys.semanticVersion, in: rootSpanAttributes) else {
      throw OTLPRequestDecoderError.missingTerraSchemaAttributes([Self.TerraContract.Keys.semanticVersion])
    }

    if !Self.TerraContract.isSupportedSchemaVersion(version) {
      throw OTLPRequestDecoderError.unsupportedTerraSchema(version: version)
    }

    guard let schemaFamily = stringValue(for: Self.TerraContract.Keys.schemaFamily, in: rootSpanAttributes),
          schemaFamily == Self.TerraContract.requiredFamily else {
      throw OTLPRequestDecoderError.unsupportedTerraSchema(
        version: "schema-family=\(stringValue(for: Self.TerraContract.Keys.schemaFamily, in: rootSpanAttributes) ?? "missing")"
      )
    }
  }

  private func extractCandidateContractAttributes(
    from spans: [Opentelemetry_Proto_Trace_V1_Span],
    fallback resourceAttributes: [String: AttributeValue]
  ) -> [String: AttributeValue] {
    var candidate = resourceAttributes
    for span in spans where span.parentSpanID.isEmpty {
      let spanAttributes = attributesDictionary(from: span.attributes)
      let relevant = spanAttributes.filter { Self.TerraContract.requiredAttributeNames.contains($0.key) }
      if !relevant.isEmpty {
        candidate.merge(relevant) { _, new in new }
      }
    }
    return candidate
  }

  private func stringValue(
    for key: String,
    in attributes: [String: AttributeValue]
  ) -> String? {
    guard case .string(let value) = attributes[key] else { return nil }
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
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
