import Foundation

/// Result of trace file discovery, including rejected filenames.
public struct TraceFileDiscoveryResult {
  public let files: [TraceFileReference]
  public let invalidFiles: [URL]
}

/// Discovers persisted trace files under the Terra traces directory.
public struct TraceFileLocator {
  public let tracesDirectoryURL: URL

  /// Creates a locator scoped to a specific traces directory.
  public init(tracesDirectoryURL: URL = Self.defaultTracesDirectoryURL()) {
    self.tracesDirectoryURL = tracesDirectoryURL
  }

  /// Returns trace files with numeric names (milliseconds since reference date), sorted by time.
  public func listTraceFiles() throws -> [TraceFileReference] {
    try listTraceFilesDetailed().files
  }

  /// Returns trace files and records files rejected for invalid filenames.
  public func listTraceFilesDetailed() throws -> TraceFileDiscoveryResult {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: tracesDirectoryURL.path) else {
      return TraceFileDiscoveryResult(files: [], invalidFiles: [])
    }

    let urls = try fileManager.contentsOfDirectory(
      at: tracesDirectoryURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )

    var files: [TraceFileReference] = []
    var invalidFiles: [URL] = []
    files.reserveCapacity(urls.count)

    for url in urls {
      let name = url.lastPathComponent
      guard let milliseconds = UInt64(name) else {
        invalidFiles.append(url)
        continue
      }
      let timestamp = Date(timeIntervalSinceReferenceDate: TimeInterval(milliseconds) / 1000.0)
      files.append(TraceFileReference(url: url, fileName: name, timestamp: timestamp))
    }

    let sortedFiles = files.sorted { $0.timestamp < $1.timestamp }
    let sortedInvalidFiles = invalidFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
    return TraceFileDiscoveryResult(files: sortedFiles, invalidFiles: sortedInvalidFiles)
  }

  /// Returns the default Terra traces directory in the user caches folder.
  public static func defaultTracesDirectoryURL() -> URL {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base
      .appendingPathComponent("opentelemetry", isDirectory: true)
      .appendingPathComponent("terra", isDirectory: true)
      .appendingPathComponent("traces", isDirectory: true)
  }
}
