import Foundation
import TerraCore
import OpenTelemetryApi
import OpenTelemetrySdk
import URLSessionInstrumentation

public enum HTTPAIInstrumentation {
    public static let defaultAIHosts: Set<String> = [
        "api.openai.com",
        "api.anthropic.com",
        "generativelanguage.googleapis.com",
        "api.together.xyz",
        "api.mistral.ai",
        "api.groq.com",
        "api.cohere.com",
        "api.fireworks.ai",
    ]

    public static let defaultOpenClawGatewayHosts: Set<String> = [
        "localhost",
        "127.0.0.1",
    ]

    private static let lock = NSLock()
    private static var instance: URLSessionInstrumentation?

    public static func install(
        hosts: Set<String> = defaultAIHosts,
        openClawGatewayHosts: Set<String> = [],
        openClawMode: String = "disabled",
        excludedEndpoints: Set<URL> = []
    ) {
        lock.lock()
        defer { lock.unlock() }

        let excludedNormalizedEndpoints = Set(excludedEndpoints.compactMap(NormalizedEndpoint.init(url:)))

        let config = URLSessionInstrumentationConfiguration(
            shouldInstrument: { request in
                guard let url = request.url, let host = url.host else { return false }
                if isEndpointExcluded(url, excludedEndpoints: excludedNormalizedEndpoints) {
                    return false
                }
                return isHostMatched(host, hosts: hosts)
                    || isHostMatched(host, hosts: openClawGatewayHosts)
            },
            nameSpan: { request in
                guard let host = request.url?.host else { return nil }
                let operation = inferredOperationName(from: request)
                if isHostMatched(host, hosts: openClawGatewayHosts) {
                    return "\(operation) openclaw.gateway"
                }
                for aiHost in hosts where isHostBoundaryMatch(host: host, target: aiHost) {
                    return "\(operation) \(host)"
                }
                return nil
            },
            spanCustomization: { request, spanBuilder in
                spanBuilder.setAttribute(key: Terra.Keys.Terra.autoInstrumented, value: true)
                spanBuilder.setAttribute(key: Terra.Keys.Terra.runtime, value: "http_api")
                spanBuilder.setAttribute(key: Terra.Keys.GenAI.operationName, value: inferredOperationName(from: request))

                if let sanitizedURL = sanitizedRequestURL(request.url) {
                    // Override URLSessionInstrumentation's default full URL capture with a query/fragment-free URL.
                    spanBuilder.setAttribute(key: "http.url", value: sanitizedURL)
                    spanBuilder.setAttribute(key: "url.full", value: sanitizedURL)
                }

                if let host = request.url?.host {
                    let isOpenClawGateway = isHostMatched(host, hosts: openClawGatewayHosts)
                    let provider = providerName(from: host, openClawGatewayHosts: openClawGatewayHosts)
                    spanBuilder.setAttribute(key: Terra.Keys.GenAI.providerName, value: provider)
                    if isOpenClawGateway {
                        spanBuilder.setAttribute(key: Terra.Keys.Terra.runtime, value: "openclaw_gateway")
                        spanBuilder.setAttribute(key: Terra.Keys.Terra.openClawGateway, value: true)
                        spanBuilder.setAttribute(key: Terra.Keys.Terra.openClawMode, value: openClawMode)
                    }
                }

                guard let body = request.httpBody,
                      let parsed = AIRequestParser.parse(body: body) else { return }

                if let model = parsed.model {
                    spanBuilder.setAttribute(key: Terra.Keys.GenAI.requestModel, value: model)
                }
                if let maxTokens = parsed.maxTokens {
                    spanBuilder.setAttribute(key: Terra.Keys.GenAI.requestMaxTokens, value: maxTokens)
                }
                if let temperature = parsed.temperature {
                    spanBuilder.setAttribute(key: Terra.Keys.GenAI.requestTemperature, value: temperature)
                }
                if let stream = parsed.stream {
                    spanBuilder.setAttribute(key: Terra.Keys.GenAI.requestStream, value: stream)
                }
            },
            receivedResponse: { _, dataOrFile, span in
                guard let data = dataOrFile as? Data,
                      let parsed = AIResponseParser.parse(data: data) else { return }

                if let model = parsed.model {
                    span.setAttribute(key: Terra.Keys.GenAI.responseModel, value: model)
                }
                if let inputTokens = parsed.inputTokens {
                    span.setAttribute(key: Terra.Keys.GenAI.usageInputTokens, value: inputTokens)
                }
                if let outputTokens = parsed.outputTokens {
                    span.setAttribute(key: Terra.Keys.GenAI.usageOutputTokens, value: outputTokens)
                }
            },
            semanticConvention: .old
        )

        if let instance {
            instance.configuration = config
        } else {
            instance = URLSessionInstrumentation(configuration: config)
        }
    }

    static func resetForTesting() {
        lock.lock()
        defer { lock.unlock() }
        instance = nil
    }

    private static func isHostMatched(_ host: String, hosts: Set<String>) -> Bool {
        hosts.contains { isHostBoundaryMatch(host: host, target: $0) }
    }

    internal static func isHostBoundaryMatch(host: String, target: String) -> Bool {
        let normalizedHost = normalizeHost(host)
        let normalizedTarget = normalizeHost(target)
        guard !normalizedHost.isEmpty, !normalizedTarget.isEmpty else { return false }
        return normalizedHost == normalizedTarget || normalizedHost.hasSuffix(".\(normalizedTarget)")
    }

    private static func normalizeHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func providerName(from host: String, openClawGatewayHosts: Set<String>) -> String {
        if isHostMatched(host, hosts: openClawGatewayHosts) { return "openclaw" }
        if isHostBoundaryMatch(host: host, target: "api.openai.com") { return "openai" }
        if isHostBoundaryMatch(host: host, target: "api.anthropic.com") { return "anthropic" }
        if isHostBoundaryMatch(host: host, target: "generativelanguage.googleapis.com") { return "google" }
        if isHostBoundaryMatch(host: host, target: "api.together.xyz") { return "together" }
        if isHostBoundaryMatch(host: host, target: "api.mistral.ai") { return "mistral" }
        if isHostBoundaryMatch(host: host, target: "api.groq.com") { return "groq" }
        if isHostBoundaryMatch(host: host, target: "api.cohere.com") { return "cohere" }
        if isHostBoundaryMatch(host: host, target: "api.fireworks.ai") { return "fireworks" }
        return host
    }

    private static func inferredOperationName(from request: URLRequest) -> String {
        let path = request.url?.path.lowercased() ?? ""
        if path.contains("/embeddings") {
            return Terra.OperationName.embeddings.rawValue
        }
        if path.contains("/moderations") {
            return Terra.OperationName.safetyCheck.rawValue
        }
        if path.contains("/chat/completions") || path.contains("/responses") || path.contains("/messages") {
            return Terra.OperationName.chat.rawValue
        }
        if path.contains("/completions") {
            return Terra.OperationName.textCompletion.rawValue
        }
        return Terra.OperationName.inference.rawValue
    }

    private static func sanitizedRequestURL(_ url: URL?) -> String? {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.string
    }

    private static func isEndpointExcluded(_ url: URL, excludedEndpoints: Set<NormalizedEndpoint>) -> Bool {
        guard let normalizedURL = NormalizedEndpoint(url: url) else { return false }
        return excludedEndpoints.contains(normalizedURL)
    }

    private struct NormalizedEndpoint: Hashable {
        let scheme: String
        let host: String
        let port: Int?
        let path: String

        init?(url: URL) {
            guard let scheme = url.scheme?.lowercased(),
                  let host = url.host?.lowercased() else {
                return nil
            }
            self.scheme = scheme
            self.host = host
            self.port = url.port
            let normalizedPath = url.path.isEmpty ? "/" : url.path
            self.path = normalizedPath
        }
    }
}
