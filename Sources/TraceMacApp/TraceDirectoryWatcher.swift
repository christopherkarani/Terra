import Foundation
import Darwin

final class TraceDirectoryWatcher {
  private let directoryURL: URL
  private let onChange: @MainActor () -> Void

  private let queue = DispatchQueue(label: "com.terra.TraceMacApp.TraceDirectoryWatcher")
  private var fileDescriptor: Int32 = -1
  private var source: DispatchSourceFileSystemObject?
  private var pendingCallback: DispatchWorkItem?

  init(directoryURL: URL, onChange: @escaping @MainActor () -> Void) {
    self.directoryURL = directoryURL
    self.onChange = onChange
  }

  func start() throws {
    guard source == nil else { return }

    let path = directoryURL.path
    fileDescriptor = open(path, O_EVTONLY)
    guard fileDescriptor != -1 else {
      throw CocoaError(.fileReadNoPermission)
    }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fileDescriptor,
      eventMask: [.write, .delete, .rename],
      queue: queue
    )

    source.setEventHandler { [weak self] in
      self?.scheduleCallback()
    }

    source.setCancelHandler { [fileDescriptor] in
      close(fileDescriptor)
    }

    self.source = source
    source.resume()
  }

  func stop() {
    pendingCallback?.cancel()
    pendingCallback = nil

    source?.cancel()
    source = nil
    fileDescriptor = -1
  }

  private func scheduleCallback() {
    pendingCallback?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      Task { @MainActor in
        self.onChange()
      }
    }
    pendingCallback = work
    queue.asyncAfter(deadline: .now() + .milliseconds(250), execute: work)
  }

  deinit {
    stop()
  }
}
