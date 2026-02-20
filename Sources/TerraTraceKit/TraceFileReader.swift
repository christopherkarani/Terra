import Foundation

/// Errors thrown when reading persisted trace files.
public enum TraceFileError: Error, Equatable {
  case fileMissing(URL)
  case readFailed(URL)
}

/// Reads raw bytes for a trace file reference.
public struct TraceFileReader {
  /// Creates a reader with default file system behavior.
  public init() {}

  /// Reads the raw contents for a trace file reference.
  public func read(file: TraceFileReference) throws -> Data {
    let url = file.url
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: url.path) else {
      throw TraceFileError.fileMissing(url)
    }
    do {
      return try Data(contentsOf: url)
    } catch {
      throw TraceFileError.readFailed(url)
    }
  }
}
