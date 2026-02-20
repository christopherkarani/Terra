import Foundation

/// Metadata for a persisted trace file on disk.
public struct TraceFileReference: Hashable {
  public let url: URL
  public let fileName: String
  public let timestamp: Date

  /// Creates a reference to a trace file at a specific URL and timestamp.
  public init(url: URL, fileName: String, timestamp: Date) {
    self.url = url
    self.fileName = fileName
    self.timestamp = timestamp
  }
}
