import Foundation
import TerraCore
import OpenTelemetryApi
import OpenTelemetrySdk
import URLSessionInstrumentation

public enum HTTPAIInstrumentation {
    struct RuntimeResolution: Equatable {
        let runtime: Terra.RuntimeKind
        let confidence: Double
        let evidence: String
    }

    private struct RequestContext {
        let request: URLRequest
        let parsedRequest: ParsedRequest?
    }

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
    private static let requestContextLock = NSLock()
    private static var requestContexts: [String: RequestContext] = [:]

    public static func install(
        hosts: Set<String> = defaultAIHosts,
        openClawGatewayHosts: Set<String> = [],
        openClawMode: String = "disabled"
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard instance == nil else { return }

        let config = URLSessionInstrumentationConfiguration(
            shouldRecordPayload: { _ in true },
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
                spanBuilder.setAttribute(key: Terra.Keys.Terra.runtime, value: Terra.RuntimeKind.httpAPI.rawValue)
                spanBuilder.setAttribute(key: Terra.Keys.Terra.runtimeClass, value: Terra.RuntimeKind.httpAPI.rawValue)
                spanBuilder.setAttribute(key: Terra.Keys.Terra.runtimeConfidence, value: 0.5)
                spanBuilder.setAttribute(key: Terra.Keys.GenAI.operationName, value: "chat")

                let parsedRequest = request.httpBody.flatMap(AIRequestParser.parse(body:))
                let runtimeResolution = resolveRuntime(for: request, parsedRequest: parsedRequest)

                if let host = request.url?.host {
                    let isOpenClawGateway = isHostMatched(host, hosts: openClawGatewayHosts)
                    let provider = providerName(from: host, openClawGatewayHosts: openClawGatewayHosts)
                    spanBuilder.setAttribute(key: Terra.Keys.GenAI.providerName, value: provider)

                    if isOpenClawGateway {
                        spanBuilder.setAttribute(key: Terra.Keys.Terra.runtime, value: Terra.RuntimeKind.openClawGateway.rawValue)
                        spanBuilder.setAttribute(key: Terra.Keys.Terra.runtimeClass, value: Terra.RuntimeKind.openClawGateway.rawValue)
                        spanBuilder.setAttribute(key: Terra.Keys.Terra.runtimeConfidence, value: 1.0)
                        spanBuilder.setAttribute(key: Terra.Keys.Terra.openClawGateway, value: true)
                        spanBuilder.setAttribute(key: Terra.Keys.Terra.openClawMode, value: openClawMode)
                    } else {
                        spanBuilder.setAttribute(key: Terra.Keys.Terra.runtime, value: runtimeResolution.runtime.rawValue)
                        spanBuilder.setAttribute(key: Terra.Keys.Terra.runtimeClass, value: runtimeResolution.runtime.rawValue)
                        spanBuilder.setAttribute(key: Terra.Keys.Terra.runtimeConfidence, value: runtimeResolution.confidence)
                        spanBuilder.setAttribute(key: "terra.runtime.evidence", value: runtimeResolution.evidence)
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
            createdRequest: { request, span in
                let parsedRequest = request.httpBody.flatMap(AIRequestParser.parse(body:))
                storeRequestContext(
                    RequestContext(request: request, parsedRequest: parsedRequest),
                    for: span
                )
            },
            receivedResponse: { response, dataOrFile, span in
                let requestContext = takeRequestContext(for: span)
                let fallbackRequest = requestContext?.request ?? response.url.map { URLRequest(url: $0) }
                let parsedRequest = requestContext?.parsedRequest
                let responseHeaders = (response as? HTTPURLResponse)?.allHeaderFields

                guard let responseData = responsePayloadData(from: dataOrFile),
                      !responseData.isEmpty
                else {
                    let runtimeResolution = resolveRuntime(
                        for: fallbackRequest,
                        parsedRequest: parsedRequest,
                        responseHeaderFields: responseHeaders
                    )
                    applyRuntimeResolution(runtimeResolution, to: span)

                    if parsedRequest?.stream == true {
                        addStreamingFallbackLifecycleEvent(
                            to: span,
                            runtime: runtimeResolution.runtime
                        )
                    }
                    return
                }

                let runtimeResolution = resolveRuntime(
                    for: fallbackRequest,
                    parsedRequest: parsedRequest,
                    responseData: responseData,
                    responseHeaderFields: responseHeaders
                )
                applyRuntimeResolution(runtimeResolution, to: span)

                let parsedResponse = AIResponseParser.parse(data: responseData)
                if let model = parsedResponse?.model {
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
                    runtimeResolution: runtimeResolution,
                    isStreamRequested: parsedRequest?.stream ?? false
                )
                guard streamIsLikely else { return }

                let parsedStream = parseStreamingResponse(
                    responseData: responseData,
                    runtime: runtimeResolution.runtime,
                    requestModel: parsedResponse?.model ?? parsedRequest?.model
                )
                applyStreamTelemetry(parsedStream, to: span)
            },
            receivedError: { _, _, _, span in
                _ = takeRequestContext(for: span)
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

        for event in parsed.stream.events {
            span.addEvent(name: event.name, attributes: event.attributes)
        }
    }

    private static func applyRuntimeResolution(_ resolution: RuntimeResolution, to span: Span) {
        span.setAttribute(key: Terra.Keys.Terra.runtime, value: .string(resolution.runtime.rawValue))
        span.setAttribute(key: Terra.Keys.Terra.runtimeClass, value: .string(resolution.runtime.rawValue))
        span.setAttribute(key: Terra.Keys.Terra.runtimeConfidence, value: .double(resolution.confidence))
        span.setAttribute(key: "terra.runtime.evidence", value: .string(resolution.evidence))
    }

    private static func addStreamingFallbackLifecycleEvent(
        to span: Span,
        runtime: Terra.RuntimeKind
    ) {
        span.addEvent(
            name: Terra.Keys.Terra.streamLifecycleEvent,
            attributes: [
                "event": .string("stream_complete_payload_unavailable"),
                Terra.Keys.Terra.stageName: .string("decode"),
                Terra.Keys.Terra.streamTokenStage: .string("decode"),
                Terra.Keys.Terra.availability: .string("payload_unavailable"),
                Terra.Keys.Terra.runtime: .string(runtime.rawValue),
            ]
        )
    }

    private static func spanContextKey(_ span: Span) -> String {
        span.context.spanId.hexString
    }

    private static func storeRequestContext(_ context: RequestContext, for span: Span) {
        requestContextLock.lock()
        requestContexts[spanContextKey(span)] = context
        requestContextLock.unlock()
    }

    private static func takeRequestContext(for span: Span) -> RequestContext? {
        requestContextLock.lock()
        defer { requestContextLock.unlock() }
        return requestContexts.removeValue(forKey: spanContextKey(span))
    }

    private static func resolveRuntime(
        for request: URLRequest?,
        parsedRequest: ParsedRequest?,
        responseData: Data? = nil,
        responseHeaderFields: [AnyHashable: Any]? = nil
    ) -> RuntimeResolution {
        guard let request, let requestURL = request.url else {
            return RuntimeResolution(runtime: .httpAPI, confidence: 0.2, evidence: "missing_request")
        }

        let host = requestURL.host ?? ""
        let path = requestURL.path.lowercased()
        let method = request.httpMethod?.lowercased() ?? ""
        let port = requestURL.port
        let isLocal = isHostBoundaryMatch(host: host, target: "localhost")
            || isHostBoundaryMatch(host: host, target: "127.0.0.1")

        var scores: [Terra.RuntimeKind: Double] = [:]
        var evidenceByRuntime: [Terra.RuntimeKind: [String]] = [:]

        func add(_ runtime: Terra.RuntimeKind, score: Double, reason: String) {
            scores[runtime, default: 0.0] += score
            evidenceByRuntime[runtime, default: []].append(reason)
        }

        if isLocal {
            add(.ollama, score: 0.2, reason: "local_host")
            add(.lmStudio, score: 0.2, reason: "local_host")
        } else {
            add(.httpAPI, score: 0.9, reason: "remote_host")
        }

        if let port, ollamaPorts.contains(port) {
            add(.ollama, score: 1.1, reason: "port_11434")
        }
        if let port, lmStudioPorts.contains(port) {
            add(.lmStudio, score: 1.1, reason: "port_1234")
        }

        if let matchedPath = ollamaPaths.first(where: { path == $0 || path.hasPrefix($0) }) {
            add(.ollama, score: 1.0, reason: "path_\(matchedPath)")
        }
        if let matchedPath = lmStudioPaths.first(where: { path == $0 || path.hasPrefix($0) }) {
            add(.lmStudio, score: 1.0, reason: "path_\(matchedPath)")
        }

        if method == "post", isLocal {
            if path.hasPrefix("/api/") {
                add(.ollama, score: 0.4, reason: "local_post_api")
            }
            if path.hasPrefix("/v1/") || path.hasPrefix("/api/v1/") {
                add(.lmStudio, score: 0.4, reason: "local_post_v1")
            }
        }

        if parsedRequest?.stream == true {
            if path.hasPrefix("/api/chat")
                || path.hasPrefix("/api/generate")
                || path.hasPrefix("/api/embeddings")
            {
                add(.ollama, score: 0.45, reason: "request_stream_ollama_path")
            }
            if path.hasPrefix("/v1/chat/completions")
                || path.hasPrefix("/v1/completions")
                || path.hasPrefix("/api/v1/chat/completions")
            {
                add(.lmStudio, score: 0.45, reason: "request_stream_lmstudio_path")
            }
        }

        if let hintRuntime = runtimeHintFromHeaders(request.allHTTPHeaderFields) {
            add(hintRuntime, score: 1.3, reason: "request_header_hint")
        }

        if let modelHint = parsedRequest?.model?.lowercased() {
            if modelHint.contains("ollama") {
                add(.ollama, score: 0.5, reason: "request_model_hint")
            }
            if modelHint.contains("lmstudio") || modelHint.contains("lm-studio") {
                add(.lmStudio, score: 0.5, reason: "request_model_hint")
            }
        }

        if let responseData,
           let responseText = String(data: responseData.prefix(64 * 1_024), encoding: .utf8) {
            let normalized = responseText.lowercased()

            if normalized.contains("\"prompt_eval_count\"")
                || normalized.contains("\"eval_duration\"")
                || normalized.contains("\"prompt_eval_duration\"")
                || normalized.contains("\"load_duration\"")
                || normalized.contains("\"done\":true")
            {
                add(.ollama, score: 1.3, reason: "response_ollama_usage")
            }

            if normalized.contains("event: model_load.")
                || normalized.contains("event: prompt_processing.")
                || normalized.contains("event: chat.")
                || normalized.contains("\"event\":\"model_load.")
                || normalized.contains("\"event\":\"prompt_processing.")
                || normalized.contains("\"event\":\"chat.")
            {
                add(.lmStudio, score: 1.3, reason: "response_lmstudio_events")
            }
        }

        if let responseHeaderFields,
           let contentType = responseHeaderValue("content-type", in: responseHeaderFields)?.lowercased() {
            if contentType.contains("text/event-stream") {
                add(.lmStudio, score: 0.8, reason: "content_type_sse")
            }
            if contentType.contains("ndjson") || contentType.contains("x-ndjson") {
                add(.ollama, score: 0.8, reason: "content_type_ndjson")
            }
        }

        let sorted = scores.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key.rawValue < rhs.key.rawValue
            }
            return lhs.value > rhs.value
        }

        guard let top = sorted.first else {
            return RuntimeResolution(runtime: .httpAPI, confidence: 0.2, evidence: "fallback_empty")
        }

        let second = sorted.dropFirst().first?.value ?? 0
        let margin = top.value - second

        if top.key != .httpAPI, margin < 0.2 {
            return RuntimeResolution(
                runtime: .httpAPI,
                confidence: 0.35,
                evidence: "ambiguous_\(top.key.rawValue)_margin_\(String(format: "%.2f", margin))"
            )
        }

        let confidence = normalizedConfidence(score: top.value, margin: margin, runtime: top.key)
        let evidence = evidenceByRuntime[top.key]?.joined(separator: ",") ?? "fallback"
        return RuntimeResolution(runtime: top.key, confidence: confidence, evidence: evidence)
    }

    private static func normalizedConfidence(
        score: Double,
        margin: Double,
        runtime: Terra.RuntimeKind
    ) -> Double {
        var confidence = min(max(score / 2.0, 0.2), 1.0)
        if margin < 0.35 {
            confidence = min(confidence, 0.65)
        }
        if runtime == .httpAPI && score < 1.2 {
            confidence = min(confidence, 0.6)
        }
        return confidence
    }

    private static func runtimeHintFromHeaders(_ headers: [String: String]?) -> Terra.RuntimeKind? {
        guard let headers else { return nil }
        for (key, value) in headers {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard normalizedKey == "x-terra-runtime"
                || normalizedKey == "x-runtime"
                || normalizedKey == "x-ai-runtime"
            else {
                continue
            }
            if let runtime = runtimeKind(fromHintValue: value) {
                return runtime
            }
        }
        return nil
    }

    private static func runtimeKind(fromHintValue value: String) -> Terra.RuntimeKind? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "ollama":
            return .ollama
        case "lmstudio", "lm_studio", "lm-studio":
            return .lmStudio
        case "http", "http_api", "httpapi":
            return .httpAPI
        case "openclaw_gateway", "openclaw-gateway", "openclaw":
            return .openClawGateway
        default:
            return nil
        }
    }

    private static func responseHeaderValue(
        _ field: String,
        in headers: [AnyHashable: Any]
    ) -> String? {
        let normalizedField = field.lowercased()
        for (key, value) in headers {
            let keyString = String(describing: key).lowercased()
            guard keyString == normalizedField else { continue }
            if let stringValue = value as? String {
                return stringValue
            }
            if let numberValue = value as? NSNumber {
                return numberValue.stringValue
            }
        }
        return nil
    }

    internal static func resolveRuntimeForTesting(
        request: URLRequest,
        parsedRequest: ParsedRequest?,
        responseData: Data? = nil,
        responseHeaderFields: [AnyHashable: Any]? = nil
    ) -> RuntimeResolution {
        resolveRuntime(
            for: request,
            parsedRequest: parsedRequest,
            responseData: responseData,
            responseHeaderFields: responseHeaderFields
        )
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
        runtimeResolution: RuntimeResolution,
        isStreamRequested: Bool
    ) -> Bool {
        if isStreamRequested {
            return true
        }

        guard let text = String(data: data.prefix(64 * 1_024), encoding: .utf8) else {
            return false
        }
        let normalized = text.lowercased()

        if runtimeResolution.runtime == .ollama {
            return normalized.contains("\"done\"")
                || normalized.contains("\"prompt_eval_count\"")
                || normalized.contains("\n{")
        }
        if runtimeResolution.runtime == .lmStudio {
            return normalized.contains("data:")
                || normalized.contains("event:")
                || normalized.contains("\"event\":\"")
        }

        return normalized.contains("data:")
            || normalized.contains("event:")
            || normalized.contains("\"prompt_eval_count\"")
            || normalized.contains("\"eval_duration\"")
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

    private static func responsePayloadData(from value: Any?) -> Data? {
        extractResponsePayloadData(from: value, depth: 0)
    }

    private static func extractResponsePayloadData(from value: Any?, depth: Int) -> Data? {
        guard depth <= 4 else { return nil }
        guard let value else { return nil }

        if let data = value as? Data {
            return data
        }
        if let data = value as? NSData {
            return data as Data
        }
        if let url = value as? URL {
            return try? Data(contentsOf: url)
        }
        if let path = value as? String {
            return try? Data(contentsOf: URL(fileURLWithPath: path))
        }
        if let dictionary = value as? [String: Any] {
            for key in ["data", "body", "payload", "response", "file", "url", "path"] {
                if let data = extractResponsePayloadData(from: dictionary[key], depth: depth + 1),
                   !data.isEmpty {
                    return data
                }
            }
        }

        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            if let child = mirror.children.first {
                return extractResponsePayloadData(from: child.value, depth: depth + 1)
            }
            return nil
        }

        for child in mirror.children {
            if let data = extractResponsePayloadData(from: child.value, depth: depth + 1),
               !data.isEmpty {
                return data
            }
        }

        return nil
    }

    #if DEBUG
    /// Best-effort reset hook for tests that need deterministic reconfiguration.
    public static func resetForTesting() {
        lock.lock()
        instance = nil
        lock.unlock()
        requestContextLock.lock()
        requestContexts.removeAll()
        requestContextLock.unlock()
    }
    #endif
}
