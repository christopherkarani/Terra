import Foundation
#if canImport(OpenTelemetryProtocolExporterCommon)
import OpenTelemetryProtocolExporterCommon
#elseif canImport(OpenTelemetryProtocolExporterGrpc)
import OpenTelemetryProtocolExporterGrpc
#elseif canImport(OpenTelemetryProtocolExporterHttp)
import OpenTelemetryProtocolExporterHttp
#elseif canImport(OpenTelemetryProtocolExporterHTTP)
import OpenTelemetryProtocolExporterHTTP
#else
#error("OpenTelemetry OTLP protobuf module not available")
#endif
import SwiftProtobuf
#if canImport(Compression)
import Compression
#endif

enum OTLPTestFixtures {
  static let traceIDHex = "0123456789abcdef0123456789abcdef"
  static let parentSpanIDHex = "0123456789abcdef"
  static let childSpanIDHex = "1111111111111111"
  static let siblingSpanIDHex = "2222222222222222"

  static let rootStart: UInt64 = 1_700_000_000_000_000_000
  static let rootEnd: UInt64 = 1_700_000_050_000_000_000
  static let childStart: UInt64 = 1_700_000_010_000_000_000
  static let childEnd: UInt64 = 1_700_000_020_000_000_000
  static let siblingStart: UInt64 = 1_700_000_030_000_000_000
  static let siblingEnd: UInt64 = 1_700_000_040_000_000_000

  static let resourceAttributes: [String: String] = [
    "service.name": "demo-service",
    "service.version": "1.0.0"
  ]

  static let spanAttributes: [(String, String)] = [
    ("terra.sample", "true"),
    ("gen_ai.model", "gpt-4o"),
    ("status.code", "ok"),
    ("span.kind", "server")
  ]

  static func makeExportRequest() -> Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest {
    let rootSpan = makeSpan(
      traceIDHex: traceIDHex,
      spanIDHex: parentSpanIDHex,
      parentSpanIDHex: nil,
      name: "root",
      kind: .server,
      status: .ok,
      startTimeUnixNano: rootStart,
      endTimeUnixNano: rootEnd,
      attributes: spanAttributes
    )

    let childSpan = makeSpan(
      traceIDHex: traceIDHex,
      spanIDHex: childSpanIDHex,
      parentSpanIDHex: parentSpanIDHex,
      name: "child",
      kind: .client,
      status: .ok,
      startTimeUnixNano: childStart,
      endTimeUnixNano: childEnd,
      attributes: [
        ("status.code", "ok"),
        ("gen_ai.operation", "chat")
      ]
    )

    var resource = Opentelemetry_Proto_Resource_V1_Resource()
    resource.attributes = resourceAttributes.map { key, value in
      makeKeyValue(key: key, stringValue: value)
    }

    var scopeSpans = Opentelemetry_Proto_Trace_V1_ScopeSpans()
    scopeSpans.spans = [rootSpan, childSpan]

    var resourceSpans = Opentelemetry_Proto_Trace_V1_ResourceSpans()
    resourceSpans.resource = resource
    resourceSpans.scopeSpans = [scopeSpans]

    var request = Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest()
    request.resourceSpans = [resourceSpans]
    return request
  }

  static func makeSiblingExportRequest() -> Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest {
    let rootSpan = makeSpan(
      traceIDHex: traceIDHex,
      spanIDHex: parentSpanIDHex,
      parentSpanIDHex: nil,
      name: "root",
      kind: .server,
      status: .ok,
      startTimeUnixNano: rootStart,
      endTimeUnixNano: rootEnd,
      attributes: [("status.code", "ok")]
    )

    let firstChild = makeSpan(
      traceIDHex: traceIDHex,
      spanIDHex: childSpanIDHex,
      parentSpanIDHex: parentSpanIDHex,
      name: "child-early",
      kind: .client,
      status: .ok,
      startTimeUnixNano: childStart,
      endTimeUnixNano: childEnd,
      attributes: [("status.code", "ok")]
    )

    let secondChild = makeSpan(
      traceIDHex: traceIDHex,
      spanIDHex: siblingSpanIDHex,
      parentSpanIDHex: parentSpanIDHex,
      name: "child-late",
      kind: .client,
      status: .ok,
      startTimeUnixNano: siblingStart,
      endTimeUnixNano: siblingEnd,
      attributes: [("status.code", "ok")]
    )

    var scopeSpans = Opentelemetry_Proto_Trace_V1_ScopeSpans()
    scopeSpans.spans = [rootSpan, secondChild, firstChild]

    var resource = Opentelemetry_Proto_Resource_V1_Resource()
    resource.attributes = resourceAttributes.map { key, value in
      makeKeyValue(key: key, stringValue: value)
    }

    var resourceSpans = Opentelemetry_Proto_Trace_V1_ResourceSpans()
    resourceSpans.resource = resource
    resourceSpans.scopeSpans = [scopeSpans]

    var request = Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest()
    request.resourceSpans = [resourceSpans]
    return request
  }

  static func serializedRequest() throws -> Data {
    try makeExportRequest().serializedData()
  }

  static func serializedSiblingRequest() throws -> Data {
    try makeSiblingExportRequest().serializedData()
  }

  static func makeSpan(
    traceIDHex: String,
    spanIDHex: String,
    parentSpanIDHex: String?,
    name: String,
    kind: Opentelemetry_Proto_Trace_V1_Span.SpanKind,
    status: Opentelemetry_Proto_Trace_V1_Status.StatusCode,
    startTimeUnixNano: UInt64,
    endTimeUnixNano: UInt64,
    attributes: [(String, String)]
  ) -> Opentelemetry_Proto_Trace_V1_Span {
    var span = Opentelemetry_Proto_Trace_V1_Span()
    span.traceID = traceIDHex.hexBytes()
    span.spanID = spanIDHex.hexBytes()
    if let parentSpanIDHex {
      span.parentSpanID = parentSpanIDHex.hexBytes()
    }
    span.name = name
    span.kind = kind
    span.startTimeUnixNano = startTimeUnixNano
    span.endTimeUnixNano = endTimeUnixNano
    span.attributes = attributes.map { key, value in makeKeyValue(key: key, stringValue: value) }

    var statusMessage = Opentelemetry_Proto_Trace_V1_Status()
    statusMessage.code = status
    span.status = statusMessage
    return span
  }

  static func makeKeyValue(key: String, stringValue: String) -> Opentelemetry_Proto_Common_V1_KeyValue {
    var value = Opentelemetry_Proto_Common_V1_AnyValue()
    value.stringValue = stringValue

    var keyValue = Opentelemetry_Proto_Common_V1_KeyValue()
    keyValue.key = key
    keyValue.value = value
    return keyValue
  }
}

extension String {
  fileprivate func hexBytes() -> Data {
    var data = Data()
    var index = startIndex
    while index < endIndex {
      let nextIndex = self.index(index, offsetBy: 2)
      let byteString = self[index..<nextIndex]
      if let byte = UInt8(byteString, radix: 16) {
        data.append(byte)
      }
      index = nextIndex
    }
    return data
  }
}

#if canImport(Compression)
enum OTLPTestCompression {
  enum CompressionError: Error {
    case encodingFailed
  }

  static func deflate(_ data: Data) throws -> Data {
    guard let result = data.withUnsafeBytes({ (rawBuffer: UnsafeRawBufferPointer) -> Data? in
      guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return nil }
      return perform(
        operation: COMPRESSION_STREAM_ENCODE,
        algorithm: COMPRESSION_ZLIB,
        source: baseAddress,
        sourceSize: data.count,
        preload: Data()
      )
    }) else {
      throw CompressionError.encodingFailed
    }
    return result
  }

  static func gzip(_ data: Data, timestamp: UInt32 = 0) throws -> Data {
    var header = Data([0x1f, 0x8b, 0x08, 0x00])
    var time = timestamp.littleEndian
    header.append(Data(bytes: &time, count: MemoryLayout<UInt32>.size))
    header.append(contentsOf: [0x00, 0x03])

    let deflated = try deflate(data)

    var result = header
    result.append(deflated)

    var crc = CRC32.checksum(data).littleEndian
    result.append(Data(bytes: &crc, count: MemoryLayout<UInt32>.size))

    var isize = UInt32(truncatingIfNeeded: data.count).littleEndian
    result.append(Data(bytes: &isize, count: MemoryLayout<UInt32>.size))

    return result
  }


  private static func perform(
    operation: compression_stream_operation,
    algorithm: compression_algorithm,
    source: UnsafePointer<UInt8>,
    sourceSize: Int,
    preload: Data
  ) -> Data? {
    guard operation == COMPRESSION_STREAM_ENCODE || sourceSize > 0 else { return nil }

    let dummyDst = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
    let dummySrc = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
    defer {
      dummyDst.deallocate()
      dummySrc.deallocate()
    }
    var stream = compression_stream(
      dst_ptr: dummyDst,
      dst_size: 0,
      src_ptr: UnsafePointer(dummySrc),
      src_size: 0,
      state: nil
    )
    let status = compression_stream_init(&stream, operation, algorithm)
    guard status != COMPRESSION_STATUS_ERROR else { return nil }
    defer { compression_stream_destroy(&stream) }

    var result = preload
    var flags: Int32 = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
    let blockLimit = 64 * 1024
    var bufferSize = Swift.max(sourceSize, 64)

    if sourceSize > blockLimit {
      bufferSize = blockLimit
    }

    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    stream.dst_ptr = buffer
    stream.dst_size = bufferSize
    stream.src_ptr = source
    stream.src_size = sourceSize

    while true {
      switch compression_stream_process(&stream, flags) {
      case COMPRESSION_STATUS_OK:
        guard stream.dst_size == 0 else { return nil }
        result.append(buffer, count: stream.dst_ptr - buffer)
        stream.dst_ptr = buffer
        stream.dst_size = bufferSize
      case COMPRESSION_STATUS_END:
        result.append(buffer, count: stream.dst_ptr - buffer)
        return result
      default:
        return nil
      }
    }
  }
}

private enum CRC32 {
  static func checksum(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xffffffff
    for byte in data {
      let index = Int((crc ^ UInt32(byte)) & 0xff)
      crc = (crc >> 8) ^ table[index]
    }
    return crc ^ 0xffffffff
  }

  private static let table: [UInt32] = {
    (0..<256).map { value in
      var crc = UInt32(value)
      for _ in 0..<8 {
        if crc & 1 == 1 {
          crc = (crc >> 1) ^ 0xedb88320
        } else {
          crc = crc >> 1
        }
      }
      return crc
    }
  }()
}
#endif
