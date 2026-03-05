import Foundation

extension Terra {
  /// OpenClaw-specific auto-instrumentation settings for `Terra.start()`.
  public struct OpenClawConfiguration: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
      case disabled
      case diagnosticsOnly
      case gatewayOnly
      case dualPath
    }

    public enum GatewayAuth: Sendable, Equatable {
      case none
      case bearer(token: String)
    }

    /// Integration mode for OpenClaw observability.
    public var mode: Mode

    /// Gateway hosts to instrument (host only, no scheme/port).
    public var gatewayHosts: Set<String>

    /// Optional gateway endpoint (for SDK clients that use a dedicated base URL).
    public var gatewayBaseURL: URL?

    /// Optional directory where diagnostics spans should be exported as JSONL.
    public var diagnosticsDirectoryURL: URL?

    /// Optional auth strategy for gateway calls.
    public var gatewayAuth: GatewayAuth

    /// Whether transparent mode is enabled for this SDK config.
    public var transparentModeEnabled: Bool

    public init(
      mode: Mode = .disabled,
      gatewayHosts: Set<String>? = nil,
      gatewayBaseURL: URL? = nil,
      diagnosticsDirectoryURL: URL? = nil,
      gatewayAuth: GatewayAuth = .none,
      transparentModeEnabled: Bool = false
    ) {
      self.mode = mode
      if let gatewayHosts {
        self.gatewayHosts = gatewayHosts
      } else {
        self.gatewayHosts = Self.defaultGatewayHosts(for: mode)
      }
      self.gatewayBaseURL = gatewayBaseURL
      self.diagnosticsDirectoryURL = diagnosticsDirectoryURL
      self.gatewayAuth = gatewayAuth
      self.transparentModeEnabled = transparentModeEnabled
    }

    public static let disabled = OpenClawConfiguration()

    public var shouldEnableGatewayInstrumentation: Bool {
      switch mode {
      case .gatewayOnly, .dualPath:
        return true
      case .disabled, .diagnosticsOnly:
        return false
      }
    }

    public var shouldEnableDiagnosticsExport: Bool {
      switch mode {
      case .diagnosticsOnly, .dualPath:
        return true
      case .disabled, .gatewayOnly:
        return false
      }
    }

    var modeString: String {
      switch mode {
      case .disabled:
        return "disabled"
      case .diagnosticsOnly:
        return "diagnostics_only"
      case .gatewayOnly:
        return "gateway_only"
      case .dualPath:
        return "dual_path"
      }
    }

    private static func defaultGatewayHosts(for mode: Mode) -> Set<String> {
      switch mode {
      case .gatewayOnly, .dualPath:
        return ["localhost", "127.0.0.1"]
      case .disabled, .diagnosticsOnly:
        return []
      }
    }
  }

  /// Proxy configuration reserved for low-level proxy instrumentation paths.
  public struct ProxyConfiguration: Sendable, Equatable {
    public struct Upstream: Sendable, Hashable {
      public var host: String
      public var port: Int

      public init(host: String, port: Int) {
        self.host = host
        self.port = port
      }

      public static func ollama(host: String = "127.0.0.1", port: Int = 11434) -> Upstream {
        Upstream(host: host, port: port)
      }

      public static func lmStudio(host: String = "127.0.0.1", port: Int = 1234) -> Upstream {
        Upstream(host: host, port: port)
      }
    }

    public var listenHost: String
    public var listenPort: Int
    public var upstreams: [Upstream]

    public init(
      listenHost: String = "127.0.0.1",
      listenPort: Int = 11435,
      upstreams: [Upstream] = [.ollama(), .lmStudio()]
    ) {
      self.listenHost = listenHost
      self.listenPort = listenPort
      self.upstreams = upstreams
    }
  }
}
