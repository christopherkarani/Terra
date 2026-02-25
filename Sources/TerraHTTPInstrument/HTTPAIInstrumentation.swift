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
        openClawMode: String = "disabled"
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard instance == nil else { return }

        let config = URLSessionInstrumentationConfiguration(
            shouldInstrument: { request in
                guard let host = request.url?.host else { return false }
                return isHostMatched(host, hosts: hosts)
                    || isHostMatched(host, hosts: openClawGatewayHosts)
            },
            nameSpan: { request in
                guard let host = request.url?.host else { return nil }
                if isHostMatched(host, hosts: openClawGatewayHosts) {
                    return "chat openclaw.gateway"
                }
                for aiHost in hosts where isHostBoundaryMatch(host: host, target: aiHost) {
                    return "chat \(host)"
                }
                return nil
            },
            spanCustomization: { request, spanBuilder in
                spanBuilder.setAttribute(key: Terra.Keys.Terra.autoInstrumented, value: true)
                spanBuilder.setAttribute(key: Terra.Keys.Terra.runtime, value: "http_api")
                spanBuilder.setAttribute(key: Terra.Keys.GenAI.operationName, value: "chat")

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

        instance = URLSessionInstrumentation(configuration: config)
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
}
