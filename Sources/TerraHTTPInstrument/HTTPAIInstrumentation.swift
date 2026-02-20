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

    public static let defaultOllamaHosts: Set<String> = [
        "127.0.0.1",
        "localhost",
    ]

    public static let defaultLMStudioHosts: Set<String> = [
        "127.0.0.1",
        "localhost",
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
                    || isHostMatched(host, hosts: defaultOllamaHosts)
                    || isHostMatched(host, hosts: defaultLMStudioHosts)
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

                let parsedRequest = request.httpBody.flatMap(AIRequestParser.parse(body:))
                let runtime = inferRuntime(for: request, parsedRequest: parsedRequest)

                if let host = request.url?.host {
                    let isOpenClawGateway = isHostMatched(host, hosts: openClawGatewayHosts)
                    let provider = providerName(from: host, openClawGatewayHosts: openClawGatewayHosts)
                    spanBuilder.setAttribute(key: Terra.Keys.GenAI.providerName, value: provider)
                    if isOpenClawGateway {
                        spanBuilder.setAttribute(key: Terra.Keys.Terra.runtime, value: Terra.RuntimeKind.openClawGateway.rawValue)
                        spanBuilder.setAttribute(key: Terra.Keys.Terra.openClawGateway, value: true)
                        spanBuilder.setAttribute(key: Terra.Keys.Terra.openClawMode, value: openClawMode)
                    } else {
                        spanBuilder.setAttribute(key: Terra.Keys.Terra.runtime, value: runtime.rawValue)
                    }
                }

                if let model = parsedRequest?.model {
                    spanBuilder.setAttribute(key: Terra.Keys.GenAI.requestModel, value: model)
                }
                if let maxTokens = parsedRequest?.maxTokens {
                    spanBuilder.setAttribute(key: Terra.Keys.GenAI.requestMaxTokens, value: maxTokens)
                }
                if let temperature = parsedRequest?.temperature {
                    spanBuilder.setAttribute(key: Terra.Keys.GenAI.requestTemperature, value: temperature)
                }
                if let stream = parsedRequest?.stream {
                    spanBuilder.setAttribute(key: Terra.Keys.GenAI.requestStream, value: stream)
                }
            },
            receivedResponse: { response, dataOrFile, span in
                guard let responseData = responsePayloadData(from: dataOrFile),
                      !responseData.isEmpty else { return }

                guard let responseURL = response.url else { return }
                let runtime = inferRuntime(
                    for: URLRequest(url: responseURL),
                    parsedRequest: nil
                )
                span.setAttribute(
                    key: Terra.Keys.Terra.runtime,
                    value: .string(runtime.rawValue)
                )

                let parsedResponse = AIResponseParser.parse(data: responseData)
                if let model = parsedResponse?.model {
                    span.setAttribute(key: Terra.Keys.GenAI.responseModel, value: .string(model))
                } else if let model = parsedResponse?.model {
                    span.setAttribute(key: Terra.Keys.GenAI.responseModel, value: .string(model))
                }
                if let inputTokens = parsedResponse?.inputTokens {
                    span.setAttribute(key: Terra.Keys.GenAI.usageInputTokens, value: .int(inputTokens))
                }
                if let outputTokens = parsedResponse?.outputTokens {
                    span.setAttribute(key: Terra.Keys.GenAI.usageOutputTokens, value: .int(outputTokens))
                }

                let streamIsLikely = isStreamingResponseCandidate(
                    data: responseData,
                    runtime: runtime,
                    isStreamRequested: false
                )

                guard streamIsLikely else { return }
                let parsedStream = parseStreamingResponse(
                    responseData: responseData,
                    runtime: runtime,
                    requestModel: parsedResponse?.model
                )
                applyStreamTelemetry(parsedStream, to: span)
            },
            semanticConvention: .stable
        )

        instance = URLSessionInstrumentation(configuration: config)
    }

    private static var ollamaPorts: Set<Int> { [11434] }
    private static var lmStudioPorts: Set<Int> { [1234] }

    private static let ollamaPaths: [String] = [
        "/api/generate",
        "/api/show",
        "/api/tags",
        "/api/chat",
        "/api/embeddings",
    ]

    private static let lmStudioPaths: [String] = [
        "/v1/chat/completions",
        "/v1/completions",
        "/v1/embeddings",
        "/api/v1/chat/completions",
    ]

    private static func parseStreamingResponse(
        responseData: Data,
        runtime: Terra.RuntimeKind,
        requestModel: String?
    ) -> ParsedResponseAndStream {
        AIResponseStreamParser.parse(
            data: responseData,
            runtime: parserRuntime(from: runtime),
            requestModel: requestModel
        )
            ?? ParsedResponseAndStream(
                response: ParsedResponse(inputTokens: nil, outputTokens: nil, model: nil),
                stream: ParsedStreamTelemetry()
            )
    }

    private static func applyStreamTelemetry(_ parsed: ParsedResponseAndStream, to span: Span) {
        if let model = parsed.response.model {
            span.setAttribute(key: Terra.Keys.GenAI.responseModel, value: .string(model))
        }
        if let promptEvalCount = parsed.stream.promptEvalTokenCount {
            span.setAttribute(key: Terra.Keys.Terra.stageTokenCount, value: .int(promptEvalCount))
            if let promptEvalDurationMs = parsed.stream.promptEvalDurationMs {
                span.setAttribute(key: Terra.Keys.Terra.latencyPromptEvalMs, value: .double(promptEvalDurationMs))
            }
        }
        if let outputCount = parsed.stream.decodeTokenCount {
            span.setAttribute(key: Terra.Keys.Terra.streamOutputTokens, value: .int(outputCount))
            if let decodeDurationMs = parsed.stream.decodeDurationMs {
                span.setAttribute(key: Terra.Keys.Terra.latencyDecodeMs, value: .double(decodeDurationMs))
            }
        }
        if let loadDurationMs = parsed.stream.loadDurationMs {
            span.setAttribute(key: Terra.Keys.Terra.latencyModelLoadMs, value: .double(loadDurationMs))
        }
        if let ttft = parsed.stream.streamTTFMS {
            span.setAttribute(key: Terra.Keys.Terra.streamTimeToFirstTokenMs, value: .double(ttft))
            span.setAttribute(key: Terra.Keys.Terra.latencyTTFTMs, value: .double(ttft))
        }
        if parsed.stream.streamChunkCount > 0 {
            span.setAttribute(key: Terra.Keys.Terra.streamChunkCount, value: .int(parsed.stream.streamChunkCount))
            if let decodeDurationMs = parsed.stream.decodeDurationMs, decodeDurationMs > 0 {
                let outputTokens = parsed.stream.decodeTokenCount ?? parsed.stream.streamChunkCount
                let tokensPerSecond = Double(outputTokens) * 1000.0 / decodeDurationMs
                span.setAttribute(key: Terra.Keys.Terra.streamTokensPerSecond, value: .double(tokensPerSecond))
            }
        }

        parsed.stream.events.forEach { event in
            span.addEvent(name: event.name, attributes: event.attributes)
        }
    }

    private static func inferRuntime(
        for request: URLRequest?,
        parsedRequest: ParsedRequest?
    ) -> Terra.RuntimeKind {
        guard let request, let requestURL = request.url else {
            return .httpAPI
        }

        let host = requestURL.host ?? ""
        let path = requestURL.path.lowercased()
        let method = request.httpMethod?.lowercased() ?? ""
        let port = requestURL.port

        if isHostBoundaryMatch(host: host, target: "localhost") ||
            isHostBoundaryMatch(host: host, target: "127.0.0.1") {
            if let port, ollamaPorts.contains(port), path.contains("api") {
                return .ollama
            }
            if let port, lmStudioPorts.contains(port), path.contains("/v1") {
                return .lmStudio
            }
            if ollamaPaths.contains(where: { path == $0 || path.hasPrefix($0) }) {
                return .ollama
            }
            if lmStudioPaths.contains(where: { path == $0 || path.hasPrefix($0) }) {
                return .lmStudio
            }
            if parsedRequest?.model?.contains("lmstudio") == true {
                return .lmStudio
            }
        }

        if method == "post" {
            if isHostBoundaryMatch(host: host, target: "localhost") ||
                isHostBoundaryMatch(host: host, target: "127.0.0.1") {
                if isHostMatched(host, hosts: defaultOllamaHosts) && path.contains("/api/") {
                    return .ollama
                }
                if isHostMatched(host, hosts: defaultLMStudioHosts) && path.hasPrefix("/api/v1") {
                    return .lmStudio
                }
            }
        }

        return .httpAPI
    }

    private static func parserRuntime(from runtime: Terra.RuntimeKind) -> AITelemetryRuntime {
        switch runtime {
        case .ollama:
            return .ollama
        case .lmStudio:
            return .lmStudio
        default:
            return .unknown
        }
    }

    private static func isStreamingResponseCandidate(
        data: Data,
        runtime: Terra.RuntimeKind,
        isStreamRequested: Bool
    ) -> Bool {
        if isStreamRequested {
            return true
        }
        guard runtime == .ollama || runtime == .lmStudio else {
            return false
        }
        guard let text = String(data: data, encoding: .utf8) else { return false }
        if runtime == .ollama {
            return text.contains("\n") || text.contains("\"done\"")
        }
        return text.contains("data:") || text.contains("event:") || text.contains("\"model\"")
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

    private static func responsePayloadData(from value: Any) -> Data? {
        if let data = value as? Data {
            return data
        }
        if let url = value as? URL {
            return try? Data(contentsOf: url)
        }
        if let path = value as? String {
            return try? Data(contentsOf: URL(fileURLWithPath: path))
        }
        return nil
    }

    #if DEBUG
    /// Best-effort reset hook for tests that need deterministic reconfiguration.
    public static func resetForTesting() {
        lock.lock()
        instance = nil
        lock.unlock()
    }
    #endif
}
