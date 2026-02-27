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

    private struct InstalledConfiguration {
        var hosts: Set<String>
        var openClawGatewayHosts: Set<String>
        var openClawMode: String

        static let `default` = InstalledConfiguration(
            hosts: HTTPAIInstrumentation.defaultAIHosts,
            openClawGatewayHosts: [],
            openClawMode: "disabled"
        )
    }

    private static let lock = NSLock()
    private static var instance: URLSessionInstrumentation?
    private static var installedConfiguration: InstalledConfiguration = .default

    public static func install(
        hosts: Set<String> = defaultAIHosts,
        openClawGatewayHosts: Set<String> = [],
        openClawMode: String = "disabled"
    ) {
        lock.lock()
        installedConfiguration = InstalledConfiguration(
            hosts: hosts,
            openClawGatewayHosts: openClawGatewayHosts,
            openClawMode: openClawMode
        )
        let shouldCreateInstance = instance == nil
        lock.unlock()

        guard shouldCreateInstance else { return }

        let config = URLSessionInstrumentationConfiguration(
            shouldInstrument: { request in
                shouldInstrument(request)
            },
            nameSpan: { request in
                spanName(for: request)
            },
            spanCustomization: { request, spanBuilder in
                customizeSpan(request: request, spanBuilder: spanBuilder)
            },
            receivedResponse: { _, dataOrFile, span in
                guard let data = responseBodyData(from: dataOrFile, maxBytes: AIRequestParser.maxBodySizeBytes),
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

        lock.lock()
        if instance == nil {
            instance = URLSessionInstrumentation(configuration: config)
        }
        lock.unlock()
    }

    static func resetForTesting() {
        lock.lock()
        defer { lock.unlock() }
        instance = nil
        installedConfiguration = .default
    }

    internal static func shouldInstrument(_ request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        let config = currentConfiguration()
        return isHostMatched(host, hosts: config.hosts)
            || isHostMatched(host, hosts: config.openClawGatewayHosts)
    }

    private static func spanName(for request: URLRequest) -> String? {
        guard let host = request.url?.host else { return nil }
        let config = currentConfiguration()
        guard isHostMatched(host, hosts: config.hosts)
            || isHostMatched(host, hosts: config.openClawGatewayHosts) else {
            return nil
        }

        let operation = operationName(for: request)
        if isHostMatched(host, hosts: config.openClawGatewayHosts) {
            return "\(operation) openclaw.gateway"
        }
        return "\(operation) \(host)"
    }

    private static func customizeSpan(request: URLRequest, spanBuilder: SpanBuilder) {
        let config = currentConfiguration()

        spanBuilder.setAttribute(key: Terra.Keys.Terra.autoInstrumented, value: true)
        spanBuilder.setAttribute(key: Terra.Keys.Terra.runtime, value: "http_api")
        spanBuilder.setAttribute(key: Terra.Keys.GenAI.operationName, value: operationName(for: request))

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

        guard let body = requestBodyData(from: request, maxBytes: AIRequestParser.maxBodySizeBytes),
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
    }

    internal static func operationName(for request: URLRequest) -> String {
        let path = request.url?.path.lowercased() ?? ""

        if path.contains("/embeddings") {
            return Terra.OperationName.embeddings.rawValue
        }
        if path.contains("/chat") || path.contains("/messages") || path.contains("/responses") || path.contains("/completions") {
            return Terra.OperationName.chat.rawValue
        }
        return Terra.OperationName.inference.rawValue
    }

    private static func requestBodyData(from request: URLRequest, maxBytes: Int) -> Data? {
        if let body = request.httpBody {
            guard body.count <= maxBytes else { return nil }
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }
        return readInputStream(stream, maxBytes: maxBytes)
    }

    private static func responseBodyData(from dataOrFile: Any?, maxBytes: Int) -> Data? {
        if let data = dataOrFile as? Data {
            guard data.count <= maxBytes else { return nil }
            return data
        }

        if let fileURL = dataOrFile as? URL {
            if let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size]) as? NSNumber,
               fileSize.intValue > maxBytes {
                return nil
            }
            guard let data = try? Data(contentsOf: fileURL), data.count <= maxBytes else {
                return nil
            }
            return data
        }

        return nil
    }

    private static func readInputStream(_ stream: InputStream, maxBytes: Int) -> Data? {
        if stream.streamStatus == .notOpen {
            stream.open()
        }
        defer { stream.close() }

        let chunkSize = 16 * 1024
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        var result = Data()

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: chunkSize)
            if bytesRead < 0 {
                return nil
            }
            if bytesRead == 0 {
                break
            }

            if result.count + bytesRead > maxBytes {
                return nil
            }
            result.append(buffer, count: bytesRead)
        }

        return result
    }

    private static func currentConfiguration() -> InstalledConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return installedConfiguration
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
