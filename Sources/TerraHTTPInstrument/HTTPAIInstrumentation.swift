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

    package struct Configuration: Sendable, Equatable {
        var hosts: Set<String>
        var openClawGatewayHosts: Set<String>
        var openClawMode: String
    }

    private static var configuration = Configuration(
        hosts: defaultAIHosts,
        openClawGatewayHosts: [],
        openClawMode: "disabled"
    )

    private static func loadConfiguration() -> Configuration {
        lock.lock()
        let config = configuration
        lock.unlock()
        return config
    }

    package static func makeConfiguration(
        hosts: Set<String>,
        openClawGatewayHosts: Set<String>,
        openClawMode: String,
        configurationProvider: (@Sendable () -> Configuration)? = nil
    ) -> URLSessionInstrumentationConfiguration {
        let initialConfiguration = Configuration(
            hosts: hosts,
            openClawGatewayHosts: openClawGatewayHosts,
            openClawMode: openClawMode
        )
        let resolveConfiguration = configurationProvider ?? { initialConfiguration }

        return URLSessionInstrumentationConfiguration(
            shouldInstrument: { request in
                let config = resolveConfiguration()
                guard !config.hosts.isEmpty || !config.openClawGatewayHosts.isEmpty else { return false }
                guard let host = request.url?.host else { return false }
                return isHostMatched(host, hosts: config.hosts)
                    || isHostMatched(host, hosts: config.openClawGatewayHosts)
            },
            nameSpan: { request in
                let config = resolveConfiguration()
                guard !config.hosts.isEmpty || !config.openClawGatewayHosts.isEmpty else { return nil }
                guard let host = request.url?.host else { return nil }
                if isHostMatched(host, hosts: config.openClawGatewayHosts) {
                    return "chat openclaw.gateway"
                }
                for aiHost in config.hosts where isHostBoundaryMatch(host: host, target: aiHost) {
                    return "chat \(host)"
                }
                return nil
            },
            spanCustomization: { request, spanBuilder in
                let config = resolveConfiguration()
                guard !config.hosts.isEmpty || !config.openClawGatewayHosts.isEmpty else { return }

                if let currentSpan = Terra.currentSpan(), !currentSpan.isEnded {
                    spanBuilder.setParent(currentSpan.otelSpan)
                }

                spanBuilder.setAttribute(key: Terra.Keys.Terra.autoInstrumented, value: true)
                spanBuilder.setAttribute(key: Terra.Keys.Terra.runtime, value: "http_api")

                let inheritedOperationName: String
                if let currentSpan = Terra.currentSpan(),
                   case let .string(value)? = currentSpan.attributeValue(for: Terra.Keys.GenAI.operationName),
                   value == "invoke_agent" {
                    inheritedOperationName = value
                } else {
                    inheritedOperationName = "chat"
                }
                spanBuilder.setAttribute(key: Terra.Keys.GenAI.operationName, value: inheritedOperationName)

                if let host = request.url?.host {
                    let isOpenClawGateway = isHostMatched(host, hosts: config.openClawGatewayHosts)
                    let provider = providerName(from: host, openClawGatewayHosts: config.openClawGatewayHosts)
                    spanBuilder.setAttribute(key: Terra.Keys.GenAI.providerName, value: provider)
                    if isOpenClawGateway {
                        spanBuilder.setAttribute(key: Terra.Keys.Terra.runtime, value: "openclaw_gateway")
                        spanBuilder.setAttribute(key: Terra.Keys.Terra.openClawGateway, value: true)
                        spanBuilder.setAttribute(key: Terra.Keys.Terra.openClawMode, value: config.openClawMode)
                    }
                }

                guard let body = request.httpBody,
                      let parsed = AIRequestParser.parse(body: body) else { return }

                applyRequestAttributes(parsed, to: spanBuilder)
            },
            injectCustomHeaders: { request, span in
                let parsedRequest = request.httpBody.flatMap(AIRequestParser.parse(body:))
                if parsedRequest?.stream == true {
                    HTTPAIStreamingObserver.shared.installIfNeeded()
                }
                HTTPAIStreamingObserver.shared.attachProperties(to: &request, span: span, parsedRequest: parsedRequest)
            },
            createdRequest: { request, span in
                let parsedRequest = request.httpBody.flatMap(AIRequestParser.parse(body:))
                if parsedRequest?.stream == true {
                    HTTPAIStreamingObserver.shared.installIfNeeded()
                }
                HTTPAIStreamingObserver.shared.register(request: request, span: span, parsedRequest: parsedRequest)
            },
            receivedResponse: { _, dataOrFile, span in
                let data = dataOrFile as? Data
                let parsed = data.flatMap(AIResponseParser.parse(data:))

                if let model = parsed?.model {
                    span.setAttribute(key: Terra.Keys.GenAI.responseModel, value: model)
                }
                if let inputTokens = parsed?.inputTokens {
                    span.setAttribute(key: Terra.Keys.GenAI.usageInputTokens, value: inputTokens)
                }
                if let outputTokens = parsed?.outputTokens {
                    span.setAttribute(key: Terra.Keys.GenAI.usageOutputTokens, value: outputTokens)
                }

                HTTPAIStreamingObserver.shared.finish(span: span, parsedResponse: parsed)
            },
            receivedError: { _, _, _, span in
                HTTPAIStreamingObserver.shared.finish(span: span, parsedResponse: nil)
            },
            semanticConvention: .old
        )
    }

    public static func install(
        hosts: Set<String> = defaultAIHosts,
        openClawGatewayHosts: Set<String> = [],
        openClawMode: String = "disabled"
    ) {
        lock.lock()
        configuration = Configuration(
            hosts: hosts,
            openClawGatewayHosts: openClawGatewayHosts,
            openClawMode: openClawMode
        )
        let shouldCreate = instance == nil && (!hosts.isEmpty || !openClawGatewayHosts.isEmpty)
        lock.unlock()

        guard shouldCreate else { return }
        let config = makeConfiguration(
            hosts: hosts,
            openClawGatewayHosts: openClawGatewayHosts,
            openClawMode: openClawMode,
            configurationProvider: { loadConfiguration() }
        )

        lock.lock()
        defer { lock.unlock() }
        guard instance == nil else { return }
        instance = URLSessionInstrumentation(configuration: config)
    }

    static func resetForTesting() {
        lock.lock()
        defer { lock.unlock() }
        instance = nil
        HTTPAIStreamingObserver.shared.reset()
        configuration = Configuration(
            hosts: defaultAIHosts,
            openClawGatewayHosts: [],
            openClawMode: "disabled"
        )
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

    private static func applyRequestAttributes(_ parsed: ParsedRequest, to spanBuilder: SpanBuilder) {
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
        if !parsed.messages.isEmpty {
            spanBuilder.setAttribute(key: Terra.Keys.GenAI.promptMessageCount, value: parsed.messages.count)
            spanBuilder.setAttribute(key: Terra.Keys.GenAI.promptRole0, value: parsed.messages[0].role)
            if Terra.shouldCaptureAutoInstrumentedPromptContent() {
                spanBuilder.setAttribute(key: Terra.Keys.GenAI.promptContent, value: parsed.messages[0].content)
            }
        }
    }
}
