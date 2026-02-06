import Foundation

actor AppLog {
  static let shared = AppLog()

  private let fileURL: URL
  private var handle: FileHandle?

  init(fileURL: URL = AppLog.defaultLogFileURL()) {
    self.fileURL = fileURL
  }

  func info(_ message: String) {
    writeLine("[INFO] \(message)")
  }

  func error(_ message: String) {
    writeLine("[ERROR] \(message)")
  }

  static func defaultLogFileURL() -> URL {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return caches
      .appendingPathComponent("TraceMacApp", isDirectory: true)
      .appendingPathComponent("logs", isDirectory: true)
      .appendingPathComponent("TraceMacApp.log", isDirectory: false)
  }

  private func writeLine(_ line: String) {
    do {
      let handle = try ensureHandle()
      let timestamp = ISO8601DateFormatter().string(from: Date())
      let text = "\(timestamp) \(line)\n"
      if let data = text.data(using: .utf8) {
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
      }
    } catch {
      // Best-effort: logging must never crash the app.
    }
  }

  private func ensureHandle() throws -> FileHandle {
    if let handle { return handle }

    let fm = FileManager.default
    try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    if !fm.fileExists(atPath: fileURL.path) {
      fm.createFile(atPath: fileURL.path, contents: nil)
    }

    let handle = try FileHandle(forWritingTo: fileURL)
    self.handle = handle
    return handle
  }
}

