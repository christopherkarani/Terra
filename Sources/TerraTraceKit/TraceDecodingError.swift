import Foundation

/// Errors that can occur when decoding persisted trace data.
public enum TraceDecodingError: Error, Equatable, CustomStringConvertible {
  case invalidFormat
  case decodingFailed(context: String)

  public var description: String {
    switch self {
    case .invalidFormat:
      return "Trace data has an invalid format."
    case .decodingFailed(let context):
      return "Trace decoding failed: \(context)"
    }
  }
}
