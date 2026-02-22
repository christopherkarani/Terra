import ArgumentParser
import TerraTraceKit

enum TraceFilterOption: ExpressibleByArgument, Hashable {
  case namePrefix(String)
  case traceID(String)

  init?(argument: String) {
    let parts = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2 else {
      return nil
    }

    let key = parts[0]
    let value = String(parts[1])
    guard !value.isEmpty else {
      return nil
    }

    switch key {
    case "name":
      self = .namePrefix(value)
    case "trace":
      self = .traceID(value)
    default:
      return nil
    }
  }
}

struct TraceFilterSelection: Hashable {
  let namePrefix: String?
  let traceID: TraceID?

  init(options: [TraceFilterOption]) throws {
    var namePrefix: String?
    var traceID: TraceID?

    for option in options {
      switch option {
      case .namePrefix(let value):
        if namePrefix != nil {
          throw ValidationError("Only one name filter is allowed. Use --filter name=<prefix> once.")
        }
        namePrefix = value
      case .traceID(let value):
        if traceID != nil {
          throw ValidationError("Only one trace filter is allowed. Use --filter trace=<traceId> once.")
        }
        guard let parsed = TraceID(hex: value) else {
          throw ValidationError("Trace ID must be a 32-character hex string.")
        }
        traceID = parsed
      }
    }

    self.namePrefix = namePrefix
    self.traceID = traceID
  }
}
