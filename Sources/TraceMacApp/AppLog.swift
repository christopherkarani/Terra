import Foundation

public actor AppLog {
  public static let shared = AppLog()

  private let fileURL: URL
  private var handle: FileHandle?
  private let formatter = ISO8601DateFormatter()
  private let maxLogSize: UInt64 = 5_000_000

  init(fileURL: URL = AppLog.defaultLogFileURL()) {
    self.fileURL = fileURL
  }

  public func info(_ message: String) {
    writeLine("[INFO] \(message)")
  }

  public func error(_ message: String) {
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
      rotateIfNeeded()
      let handle = try ensureHandle()
      let timestamp = formatter.string(from: Date())
      let text = "\(timestamp) \(line)\n"
      if let data = text.data(using: .utf8) {
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
      }
    } catch {
      // Best-effort: logging must never crash the app.
    }
  }

  private func rotateIfNeeded() {
    let fm = FileManager.default
    let path = fileURL.path
    guard fm.fileExists(atPath: path),
          let attrs = try? fm.attributesOfItem(atPath: path),
          let size = attrs[.size] as? UInt64,
          size > maxLogSize
    else { return }

    // Close the current handle before rotating.
    try? handle?.close()
    handle = nil

    let backup1 = fileURL.path.appending(".1")
    let backup2 = fileURL.path.appending(".2")

    // Delete .2 if it exists, then rename .1 -> .2, current -> .1.
    try? fm.removeItem(atPath: backup2)
    if fm.fileExists(atPath: backup1) {
      try? fm.moveItem(atPath: backup1, toPath: backup2)
    }
    try? fm.moveItem(atPath: path, toPath: backup1)
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
