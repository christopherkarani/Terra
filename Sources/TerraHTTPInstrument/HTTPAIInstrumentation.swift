import Foundation
import TerraCore
import OpenTelemetryApi
import OpenTelemetrySdk
import URLSessionInstrumentation
import os

private let logger = Logger(subsystem: "io.opentelemetry.terra", category: "HTTPAIInstrumentation")

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
        // P1-8: provider drift fixes — match by suffix so subdomains resolve.
        // `openai.azure.com` covers `<resource>.openai.azure.com`.
        "openai.azure.com",
        // Bedrock regional runtime — matched by the prefix-aware pattern set
        // below, NOT by suffix-only `amazonaws.com` (which would match every
        // AWS service). Sentinel value retained here so configurations that
        // round-trip through `Set<String>` see Bedrock present.
        "bedrock-runtime.amazonaws.com",
        "api.deepseek.com",
        "api.x.ai",
        "openrouter.ai",
        "api.perplexity.ai",
    ]

    /// Hosts that require `bedrock-runtime.<region>.amazonaws.com` style
    /// region-wildcard matching. Kept separate from `defaultAIHosts` so the
    /// suffix-based matcher in `isHostBoundaryMatch` does not accidentally
    /// promote unrelated AWS services.
    private static let regionalAWSAIHostPrefixes: [String] = [
        "bedrock-runtime.",
    ]

    /// Cap response-body capture at 1 MiB. Anything larger is dropped before
    /// JSON parsing to prevent memory blow-up on misconfigured streaming
    /// endpoints. SSE streams under this cap retain full fidelity for token
    /// extraction.
    private static let maxResponseBodyBytes = 1_048_576

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
            // P0-4 fix: opt the upstream `URLSessionInstrumentation` into
            // payload buffering for the session-delegate code path. Without
            // this, the delegate buffers nothing and `receivedResponse`
            // arrives with `dataOrFile == nil`, so `gen_ai.usage.*` and
            // `gen_ai.response.model` are never set. The completion-handler
            // code path in upstream URLSessionInstrumentation already passes
            // body bytes through `dataOrFile` regardless of this flag, so
            // returning `true` is purely additive (no behavior change for
            // completion-handler callers).
            //
            // Note: the upstream `shouldRecordPayload` closure receives a
            // `URLSession`, not a `URLRequest`, so we cannot host-match here.
            // Returning `true` is safe because `shouldInstrument` already
            // gates *which* requests trigger any logging at all — payloads
            // are only buffered for already-instrumented requests.
            shouldRecordPayload: { _ in true },
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

                // Bonus correctness fix: route through cached parser so
                // `JSONSerialization.jsonObject` runs at most once per body
                // across spanCustomization → injectCustomHeaders → createdRequest.
                guard let parsed = parsedRequestBody(for: request) else { return }

                applyRequestAttributes(parsed, to: spanBuilder)
            },
            injectCustomHeaders: { request, span in
                let parsedRequest = parsedRequestBody(for: request)
                if parsedRequest?.stream == true {
                    HTTPAIStreamingObserver.shared.installIfNeeded()
                }
                HTTPAIStreamingObserver.shared.attachProperties(to: &request, span: span, parsedRequest: parsedRequest)
            },
            createdRequest: { request, span in
                if let sanitizedURL = sanitizedURLString(request.url) {
                    span.setAttribute(key: "http.url", value: sanitizedURL)
                    span.setAttribute(key: "url.full", value: sanitizedURL)
                }
                let parsedRequest = parsedRequestBody(for: request)
                if parsedRequest?.stream == true {
                    HTTPAIStreamingObserver.shared.installIfNeeded()
                }
                HTTPAIStreamingObserver.shared.register(request: request, span: span, parsedRequest: parsedRequest)
            },
            receivedResponse: { _, dataOrFile, span in
                let rawData = dataOrFile as? Data
                let cappedData: Data?
                if let rawData {
                    if rawData.count > maxResponseBodyBytes {
                        logger.debug(
                            "Response body exceeds 1 MiB cap (\(rawData.count) bytes); skipping body parse"
                        )
                        cappedData = nil
                    } else {
                        cappedData = rawData
                    }
                } else {
                    cappedData = nil
                }

                // P0-3 fix: SUMMARY-ONLY streaming summarization. When the
                // buffered body belongs to a registered streaming span, derive
                // SSE-line count + output tokens BEFORE finish so the resulting
                // span carries both the raw response attributes and the
                // streaming summary attributes (terra.stream.completed, TTFT,
                // chunk_count, output tokens).
                if let cappedData,
                   let registeredRequest = HTTPAIStreamingObserver.shared.registeredRequest(forSpan: span) {
                    HTTPAIStreamingObserver.shared.recordCompletedStreamBody(
                        for: registeredRequest,
                        data: cappedData
                    )
                }

                let parsed = cappedData.flatMap(AIResponseParser.parse(data:))

                if let model = parsed?.model {
                    span.setAttribute(key: Terra.Keys.GenAI.responseModel, value: model)
                }
                if let inputTokens = parsed?.inputTokens {
                    span.setAttribute(key: Terra.Keys.GenAI.usageInputTokens, value: inputTokens)
                }
                if let outputTokens = parsed?.outputTokens {
                    span.setAttribute(key: Terra.Keys.GenAI.usageOutputTokens, value: outputTokens)
                }

                // Defensive fallback: SSE bodies are not parseable as a single
                // JSON object, so AIResponseParser returns nil for them. Run
                // the streaming chunk parser to surface output tokens on
                // streaming responses where the response model is unknown.
                if parsed?.outputTokens == nil, let cappedData,
                   let outputTokens = AIStreamingChunkParser.outputTokens(from: cappedData) {
                    span.setAttribute(key: Terra.Keys.GenAI.usageOutputTokens, value: outputTokens)
                }

                HTTPAIStreamingObserver.shared.finish(span: span, parsedResponse: parsed)
            },
            receivedError: { error, _, _, span in
                HTTPAIStreamingObserver.shared.finishWithError(span: span, error: error)
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
        let existingInstance = instance
        let hasInstrumentedHosts = !hosts.isEmpty || !openClawGatewayHosts.isEmpty
        let shouldCreate = existingInstance == nil && hasInstrumentedHosts
        lock.unlock()

        guard hasInstrumentedHosts else { return }
        let config = makeConfiguration(
            hosts: hosts,
            openClawGatewayHosts: openClawGatewayHosts,
            openClawMode: openClawMode,
            configurationProvider: { loadConfiguration() }
        )

        if let existingInstance {
            existingInstance.configuration = config
            return
        }

        guard shouldCreate else { return }
        lock.lock()
        defer { lock.unlock() }
        if let instance {
            instance.configuration = config
            return
        }
        instance = URLSessionInstrumentation(configuration: config)
    }

    static func resetForTesting() {
        lock.lock()
        defer { lock.unlock() }
        // URLSessionInstrumentation installs process-wide hooks that are not
        // reliably uninstalled/reinstalled inside one test process. Keep the
        // retained instance alive and reset only Terra-owned mutable state.
        HTTPAIStreamingObserver.shared.reset()
        configuration = Configuration(
            hosts: defaultAIHosts,
            openClawGatewayHosts: [],
            openClawMode: "disabled"
        )
    }

    private static func isHostMatched(_ host: String, hosts: Set<String>) -> Bool {
        if hosts.contains(where: { isHostBoundaryMatch(host: host, target: $0) }) { return true }
        return matchesRegionalAWSHostPrefix(host) && hosts.contains("bedrock-runtime.amazonaws.com")
    }

    internal static func isHostBoundaryMatch(host: String, target: String) -> Bool {
        let normalizedHost = normalizeHost(host)
        let normalizedTarget = normalizeHost(target)
        guard !normalizedHost.isEmpty, !normalizedTarget.isEmpty else { return false }
        if normalizedHost == normalizedTarget || normalizedHost.hasSuffix(".\(normalizedTarget)") {
            return true
        }
        // Bedrock regional hosts: `bedrock-runtime.<region>.amazonaws.com`
        // matches the canonical sentinel `bedrock-runtime.amazonaws.com`.
        if normalizedTarget == "bedrock-runtime.amazonaws.com",
           matchesRegionalAWSHostPrefix(normalizedHost) {
            return true
        }
        return false
    }

    private static func matchesRegionalAWSHostPrefix(_ host: String) -> Bool {
        let normalized = normalizeHost(host)
        guard normalized.hasSuffix(".amazonaws.com") else { return false }
        return regionalAWSAIHostPrefixes.contains { prefix in
            normalized.hasPrefix(prefix)
        }
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
        if isHostBoundaryMatch(host: host, target: "openai.azure.com") { return "azure_openai" }
        if matchesRegionalAWSHostPrefix(host) { return "bedrock" }
        if isHostBoundaryMatch(host: host, target: "api.deepseek.com") { return "deepseek" }
        if isHostBoundaryMatch(host: host, target: "api.x.ai") { return "x_ai" }
        if isHostBoundaryMatch(host: host, target: "openrouter.ai") { return "openrouter" }
        if isHostBoundaryMatch(host: host, target: "api.perplexity.ai") { return "perplexity" }
        return host
    }

    /// Boxed cache entry. `NSCache` requires reference values; we use an
    /// optional payload so a nil parse result still occupies a slot and
    /// doesn't trigger redundant re-parsing for malformed bodies.
    private final class ParsedRequestBox {
        let parsed: ParsedRequest?
        init(_ parsed: ParsedRequest?) { self.parsed = parsed }
    }

    /// Bounded cache so we parse each request body at most once across
    /// `spanCustomization` → `injectCustomHeaders` → `createdRequest` for
    /// the same `URLRequest`. Keyed by the absolute URL prefixed-and-joined
    /// with the body bytes so identical bodies on different URLs (Azure
    /// deployment vs. Gemini vs. Bedrock model variant) keep distinct entries
    /// while retries on the same URL remain hot.
    private static let parsedRequestCache: NSCache<NSData, ParsedRequestBox> = {
        let cache = NSCache<NSData, ParsedRequestBox>()
        cache.countLimit = 64
        return cache
    }()

    /// Returns the parsed AI request body, or nil if the request has no
    /// inspectable body (streamed bodies are intentionally ignored). The
    /// result is cached so repeated calls for the same body do at most one
    /// `JSONSerialization.jsonObject` invocation.
    ///
    /// The URL is consulted as a fallback for the model name when the body
    /// lacks one — Azure OpenAI bodies omit it (deployment is in the URL),
    /// Gemini puts the model name in the path, and Bedrock invoke-model uses
    /// `/model/<modelId>/invoke[-with-response-stream]`.
    static func parsedRequestBody(for request: URLRequest) -> ParsedRequest? {
        guard request.httpBodyStream == nil else { return nil }
        guard let body = request.httpBody else { return nil }

        // Cache key folds the absolute URL in front of the body bytes so
        // identical bodies on different URLs (Azure deployment vs. Gemini
        // vs. Bedrock model variant) cache distinct parsed results, while
        // retries on the same URL with the same body share a hit.
        let urlBytes = (request.url?.absoluteString ?? "").data(using: .utf8) ?? Data()
        var keyBuffer = Data(capacity: urlBytes.count + 1 + body.count)
        keyBuffer.append(urlBytes)
        keyBuffer.append(0x1F) // unit-separator delimiter
        keyBuffer.append(body)
        let key = keyBuffer as NSData

        if let cached = parsedRequestCache.object(forKey: key) {
            return cached.parsed
        }

        let parsed = AIRequestParser.parse(body: body, url: request.url)
        parsedRequestCache.setObject(ParsedRequestBox(parsed), forKey: key)
        return parsed
    }

    package static func sanitizedURLString(_ url: URL?) -> String? {
        guard let url else { return nil }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.user = nil
        components.password = nil
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.string
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
            for (key, value) in Terra.autoInstrumentedPromptAttributes(
                for: parsed.messages[0].content
            ) {
                spanBuilder.setAttribute(key: key, value: value)
            }
        }
    }
}
