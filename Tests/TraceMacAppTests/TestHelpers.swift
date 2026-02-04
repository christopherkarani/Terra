import Foundation
import TerraTraceKit

func makeTraceID(_ hex: String) -> TraceID {
  guard let traceID = TraceID(hex: hex) else {
    fatalError("Invalid trace hex: \(hex)")
  }
  return traceID
}

func makeSpanID(_ hex: String) -> SpanID {
  guard let spanID = SpanID(hex: hex) else {
    fatalError("Invalid span hex: \(hex)")
  }
  return spanID
}

func makeSpan(
  traceIDHex: String,
  spanIDHex: String,
  parentSpanIDHex: String? = nil,
  name: String,
  startTimeUnixNano: UInt64,
  endTimeUnixNano: UInt64
) -> SpanRecord {
  let traceID = makeTraceID(traceIDHex)
  let spanID = makeSpanID(spanIDHex)
  let parentSpanID = parentSpanIDHex.map(makeSpanID)

  let attributes = Attributes(dictionary: ["test": .string("value")])
  let resource = Resource(attributes: Attributes(dictionary: [:]))

  return SpanRecord(
    traceID: traceID,
    spanID: spanID,
    parentSpanID: parentSpanID,
    name: name,
    kind: .server,
    status: .ok,
    startTimeUnixNano: startTimeUnixNano,
    endTimeUnixNano: endTimeUnixNano,
    attributes: attributes,
    resource: resource
  )
}
