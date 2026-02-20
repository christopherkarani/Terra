import Foundation
import TerraCore

private enum TerraHTTPProxyMarker {
  static let header = "X-Terra-Proxy"
  static let value = "active"
}

enum TerraHTTPProxy {
  private static let lock = NSLock()
  private static var installed = false
  private static var configuration: Terra.ProxyConfiguration?

  static func install(_ newConfiguration: Terra.ProxyConfiguration) {
    lock.lock()
    defer { lock.unlock() }

    configuration = newConfiguration
    guard !installed else { return }
    URLProtocol.registerClass(TerraHTTPProxyURLProtocol.self)
    installed = true
  }

  static func uninstall() {
    lock.lock()
    defer { lock.unlock() }

    guard installed else { return }
    URLProtocol.unregisterClass(TerraHTTPProxyURLProtocol.self)
    installed = false
    configuration = nil
  }

  #if DEBUG
  static func resetForTesting() {
    uninstall()
  }
  #endif

  static func shouldProxy(_ request: URLRequest) -> (Bool, Terra.ProxyConfiguration.Upstream?) {
    guard
      let config = currentConfiguration(),
      let url = request.url,
      let host = url.host,
      let port = url.port ?? defaultPort(for: url.scheme)
    else {
      return (false, nil)
    }
    if !hostMatches(host: host, target: config.listenHost) || port != config.listenPort {
      return (false, nil)
    }
    if request.value(forHTTPHeaderField: TerraHTTPProxyMarker.header) == TerraHTTPProxyMarker.value {
      return (false, nil)
    }
    return (true, config.upstreams.first)
  }

  private static func currentConfiguration() -> Terra.ProxyConfiguration? {
    lock.lock()
    defer { lock.unlock() }
    return configuration
  }

  private static func hostMatches(host: String, target: String) -> Bool {
    let normalizedHost = normalize(host)
    return normalizedHost == normalize(target)
  }

  private static func normalize(_ host: String) -> String {
    host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private static func defaultPort(for scheme: String?) -> Int? {
    guard let scheme else { return nil }
    switch scheme.lowercased() {
    case "https":
      return 443
    case "http":
      return 80
    default:
      return nil
    }
  }
}

private final class TerraHTTPProxyURLProtocol: URLProtocol {
  private enum TransportError: Error {
    case noUpstream
  }

  private var forwardingTask: URLSessionDataTask?
  private var forwardingSession: URLSession?

  override class func canInit(with request: URLRequest) -> Bool {
    TerraHTTPProxy.shouldProxy(request).0
  }

  override class func canInit(with task: URLSessionTask) -> Bool {
    guard let request = task.currentRequest ?? task.originalRequest else { return false }
    return TerraHTTPProxy.shouldProxy(request).0
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let decision = requestAndUpstream()
    guard
      decision.0,
      let upstream = decision.1,
      let proxyRequest = proxiedRequest(to: upstream)
    else {
      client?.urlProtocol(self, didFailWithError: TransportError.noUpstream)
      return
    }

    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.timeoutIntervalForResource = 120
    sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData

    let session = URLSession(configuration: sessionConfiguration)
    forwardingSession = session
    forwardingTask = session.dataTask(with: proxyRequest) { [weak self] data, response, error in
      guard let self else { return }
      if let error {
        self.client?.urlProtocol(self, didFailWithError: error)
        return
      }
      if let response = response as? HTTPURLResponse {
        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      }
      if let data {
        self.client?.urlProtocol(self, didLoad: data)
      }
      self.client?.urlProtocolDidFinishLoading(self)
    }
    forwardingTask?.resume()
  }

  override func stopLoading() {
    forwardingTask?.cancel()
    forwardingTask = nil
    forwardingSession?.invalidateAndCancel()
    forwardingSession = nil
  }

  private func requestAndUpstream() -> (Bool, Terra.ProxyConfiguration.Upstream?) {
    TerraHTTPProxy.shouldProxy(request)
  }

  private func proxiedRequest(to upstream: Terra.ProxyConfiguration.Upstream) -> URLRequest? {
    guard let originalURL = request.url else { return nil }
    var components = URLComponents(url: originalURL, resolvingAgainstBaseURL: false)
    components?.host = upstream.host
    components?.port = upstream.port
    guard let rewrittenURL = components?.url else {
      return nil
    }

    var forwarded = request
    forwarded.url = rewrittenURL
    var headers = forwarded.allHTTPHeaderFields ?? [:]
    headers[TerraHTTPProxyMarker.header] = TerraHTTPProxyMarker.value
    forwarded.allHTTPHeaderFields = headers
    return forwarded
  }
}
