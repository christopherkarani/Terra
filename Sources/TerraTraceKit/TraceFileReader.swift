import Foundation

/// Errors thrown when reading persisted trace files.
public enum TraceFileError: Error, Equatable {
  case fileMissing(URL)
  case fileTooLarge(URL, actualBytes: Int, maxBytes: Int)
  case readFailed(URL)
}

/// Reads raw bytes for a trace file reference.
public struct TraceFileReader {
  public let maxFileSizeBytes: Int

  /// Creates a reader with default file system behavior.
  public init(maxFileSizeBytes: Int = 50 * 1024 * 1024) {
    self.maxFileSizeBytes = maxFileSizeBytes
  }

  /// Reads the raw contents for a trace file reference.
  public func read(file: TraceFileReference) throws -> Data {
    let url = file.url
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: url.path) else {
      throw TraceFileError.fileMissing(url)
    }

    do {
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }

      let initialSize = try handle.seekToEnd()
      if initialSize > UInt64(maxFileSizeBytes) {
        let actualBytes = Int(initialSize > UInt64(Int.max) ? UInt64(Int.max) : initialSize)
        throw TraceFileError.fileTooLarge(url, actualBytes: actualBytes, maxBytes: maxFileSizeBytes)
      }
      try handle.seek(toOffset: 0)

      let data = try handle.read(upToCount: maxFileSizeBytes + 1) ?? Data()
      if data.count > maxFileSizeBytes {
        throw TraceFileError.fileTooLarge(url, actualBytes: data.count, maxBytes: maxFileSizeBytes)
      }
      return data
    } catch let fileError as TraceFileError {
      throw fileError
    } catch {
      throw TraceFileError.readFailed(url)
    }
  }
}
