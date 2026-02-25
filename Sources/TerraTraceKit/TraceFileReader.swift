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
      let attributes = try fileManager.attributesOfItem(atPath: url.path)
      if let sizeValue = attributes[.size] as? NSNumber {
        let size = sizeValue.intValue
        if size > maxFileSizeBytes {
          throw TraceFileError.fileTooLarge(url, actualBytes: size, maxBytes: maxFileSizeBytes)
        }
      }
    } catch let fileError as TraceFileError {
      throw fileError
    } catch {
      throw TraceFileError.readFailed(url)
    }

    do {
      return try Data(contentsOf: url)
    } catch {
      throw TraceFileError.readFailed(url)
    }
  }
}
