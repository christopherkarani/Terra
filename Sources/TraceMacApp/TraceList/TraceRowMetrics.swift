import Foundation
import TerraTraceKit
import OpenTelemetryApi

/// Lightweight value type extracting per-trace performance data from span attributes.
struct TraceRowMetrics {
    let runtime: TraceRuntimeFilter
    let modelName: String?
    let ttftMs: Double?
    let tokensPerSec: Double?

    init(trace: Trace) {
        self.runtime = trace.detectedRuntime

        var model: String?
        var ttft: Double?
        var tps: Double?

        for span in trace.spans {
            let attrs = span.attributes

            if model == nil {
                model = Self.stringAttribute(attrs["gen_ai.request.model"])
                    ?? Self.stringAttribute(attrs["gen_ai.response.model"])
            }

            if ttft == nil {
                ttft = Self.doubleAttribute(attrs["terra.latency.ttft_ms"])
                    ?? Self.doubleAttribute(attrs["terra.stream.time_to_first_token_ms"])
            }

            if tps == nil {
                tps = Self.doubleAttribute(attrs["terra.stream.tokens_per_second"])
            }

            if model != nil && ttft != nil && tps != nil { break }
        }

        self.modelName = model.map(Self.shortenModelName)
        self.ttftMs = ttft
        self.tokensPerSec = tps
    }

    // MARK: - Formatting

    /// TTFT: <1000ms → "340ms", ≥1000ms → "1.2s"
    var formattedTTFT: String? {
        guard let ttftMs else { return nil }
        let seconds = max(0, ttftMs / 1000)
        if seconds < 1 {
            return "\(Int((seconds * 1000).rounded()))ms"
        }
        return String(format: "%.1fs", seconds)
    }

    /// Tok/s: "42 tok/s"
    var formattedTokensPerSec: String? {
        guard let tokensPerSec, tokensPerSec > 0 else { return nil }
        return String(format: "%.0f tok/s", tokensPerSec)
    }

    // MARK: - Private

    /// Shorten full model paths: "meta-llama/llama-3.2-1b-instruct:Q4_K_M" → "llama-3.2-1b-instruct:Q4_K_M"
    private static func shortenModelName(_ name: String) -> String {
        if let lastSlash = name.lastIndex(of: "/") {
            return String(name[name.index(after: lastSlash)...])
        }
        return name
    }

    private static func stringAttribute(_ value: OpenTelemetryApi.AttributeValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case .string(let s) where !s.isEmpty: return s
        default: return nil
        }
    }

    private static func doubleAttribute(_ value: OpenTelemetryApi.AttributeValue?) -> Double? {
        guard let value else { return nil }
        switch value {
        case .double(let v): return v > 0 ? v : nil
        case .int(let v): return v > 0 ? Double(v) : nil
        case .string(let s): return Double(s).flatMap { $0 > 0 ? $0 : nil }
        default: return nil
        }
    }
}
