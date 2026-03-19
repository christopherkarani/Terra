import Foundation

final class BonjourTerraDashboardDiscovery: NSObject, TerraDashboardDiscovering, @unchecked Sendable {
  fileprivate static let serviceType = "_terra-otlp._tcp."
  private let lock = NSLock()
  private var activeDiscoveries: [UUID: DiscoveryBridge] = [:]

  func discoverEndpoint(timeout: Duration) async -> URL? {
    let discoveryID = UUID()
    return await withCheckedContinuation { continuation in
      let bridge = DiscoveryBridge(
        continuation: continuation,
        timeout: timeout,
        onFinish: { [weak self] in
          self?.releaseDiscovery(id: discoveryID)
        }
      )
      retainDiscovery(bridge, id: discoveryID)
      bridge.start()
    }
  }

  private func retainDiscovery(_ bridge: DiscoveryBridge, id: UUID) {
    lock.withLock {
      activeDiscoveries[id] = bridge
    }
  }

  private func releaseDiscovery(id: UUID) {
    _ = lock.withLock {
      activeDiscoveries.removeValue(forKey: id)
    }
  }
}

private final class DiscoveryBridge: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
  private let continuation: CheckedContinuation<URL?, Never>
  private let timeout: Duration
  private let onFinish: @Sendable () -> Void
  private let browser = NetServiceBrowser()
  private var services: [NetService] = []
  private var timeoutTask: Task<Void, Never>?
  private var didResume = false
  private let lock = NSLock()

  init(
    continuation: CheckedContinuation<URL?, Never>,
    timeout: Duration,
    onFinish: @escaping @Sendable () -> Void
  ) {
    self.continuation = continuation
    self.timeout = timeout
    self.onFinish = onFinish
  }

  func start() {
    browser.delegate = self
    timeoutTask = Task { [weak self] in
      guard let self else { return }
      let components = timeout.components
      let seconds = max(0, components.seconds)
      let attoseconds = max(0, components.attoseconds)
      let nanos = UInt64(seconds) * 1_000_000_000 + UInt64(attoseconds / 1_000_000_000)
      try? await Task.sleep(nanoseconds: nanos)
      finish(with: nil)
    }
    browser.searchForServices(ofType: BonjourTerraDashboardDiscovery.serviceType, inDomain: "")
  }

  func netServiceBrowser(
    _ browser: NetServiceBrowser,
    didFind service: NetService,
    moreComing: Bool
  ) {
    services.append(service)
    service.delegate = self
    service.resolve(withTimeout: max(0.5, Double(timeout.components.seconds)))
  }

  func netServiceDidResolveAddress(_ sender: NetService) {
    let host = sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    guard let host, sender.port > 0 else { return }
    finish(with: URL(string: "http://\(host):\(sender.port)"))
  }

  func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
    _ = errorDict
  }

  func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
    _ = browser
  }

  func netServiceBrowser(
    _ browser: NetServiceBrowser,
    didNotSearch errorDict: [String : NSNumber]
  ) {
    _ = browser
    _ = errorDict
    finish(with: nil)
  }

  private func finish(with url: URL?) {
    lock.lock()
    guard !didResume else {
      lock.unlock()
      return
    }
    didResume = true
    lock.unlock()

    timeoutTask?.cancel()
    browser.stop()
    continuation.resume(returning: url)
    onFinish()
  }
}
