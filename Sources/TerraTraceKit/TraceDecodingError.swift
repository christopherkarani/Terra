import Foundation

/// Errors that can occur when decoding persisted trace data.
public enum TraceDecodingError: Error, Equatable {
  case invalidFormat
  case decodingFailed
}
