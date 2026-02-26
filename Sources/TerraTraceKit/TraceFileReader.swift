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
      defer {
        try? handle.close()
      }

      var output = Data()
      output.reserveCapacity(min(maxFileSizeBytes, 64 * 1024))

      while true {
        let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
        if chunk.isEmpty {
          break
        }
        let projectedSize = output.count + chunk.count
        if projectedSize > maxFileSizeBytes {
          throw TraceFileError.fileTooLarge(url, actualBytes: projectedSize, maxBytes: maxFileSizeBytes)
        }
        output.append(chunk)
      }
      return output
    } catch let fileError as TraceFileError {
      throw fileError
    } catch {
      throw TraceFileError.readFailed(url)
    }
  }
}
