import Foundation
import TerraTraceKit
import OpenTelemetryApi

struct DashboardMetrics {
    let totalTraces: Int
    let totalSpans: Int
    let averageDuration: TimeInterval
    let errorRate: Double
    let uniqueAgents: Int
    let p50Duration: TimeInterval
    let p95Duration: TimeInterval
    let p99Duration: TimeInterval
    let ttftP50: TimeInterval
    let ttftP95: TimeInterval
    let ttftP99: TimeInterval
    let e2eP50: TimeInterval
    let e2eP95: TimeInterval
    let e2eP99: TimeInterval
    let promptEvalP50: TimeInterval
    let promptEvalP95: TimeInterval
    let promptEvalP99: TimeInterval
    let decodeP50: TimeInterval
    let decodeP95: TimeInterval
    let decodeP99: TimeInterval
    let promptDecodeSplit: Double
    let stalledTokenCount: Int
    let stalledTokenRate: Double
    let recommendationCount: Int
    let anomalyCount: Int
    let hardwareTelemetryEventCount: Int
    let runtimeCounts: [TraceRuntimeFilter: Int]
}

enum DashboardViewModel {

    static func compute(from traces: [Trace]) -> DashboardMetrics {
        let totalTraces = traces.count
        let totalSpans = traces.reduce(0) { $0 + $1.spans.count }

        let averageDuration: TimeInterval
        if traces.isEmpty {
            averageDuration = 0
        } else {
            averageDuration = traces.reduce(0.0) { $0 + $1.duration } / Double(traces.count)
        }

        let errorRate: Double
        if traces.isEmpty {
            errorRate = 0
        } else {
            let errorCount = traces.filter(\.hasError).count
            errorRate = Double(errorCount) / Double(traces.count)
        }

        var agentNames = Set<String>()
        for trace in traces {
            for span in trace.spans {
                if let value = span.attributes["gen_ai.agent.name"] {
                    agentNames.insert(value.description)
                }
            }
        }

        let sortedDurations = traces.map(\.duration).sorted()
        let p50 = percentile(sortedDurations, 0.50)
        let p95 = percentile(sortedDurations, 0.95)
        let p99 = percentile(sortedDurations, 0.99)

        let allSpanAttributes = traces.flatMap(\.spans).flatMap { $0.events }

        let ttftSamples = traces.flatMap(\.spans).compactMap {
            attributeToSeconds($0.attributes["terra.latency.ttft_ms"])
        }
        let e2eSamples = traces.flatMap(\.spans).compactMap {
            attributeToSeconds($0.attributes["terra.latency.e2e_ms"])
        }
        let promptEvalSamples = traces.flatMap(\.spans).compactMap {
            attributeToSeconds($0.attributes["terra.latency.prompt_eval_ms"])
        }
        let decodeSamples = traces.flatMap(\.spans).compactMap {
            attributeToSeconds($0.attributes["terra.latency.decode_ms"])
        }

        let stalledEvents = allSpanAttributes.filter { event in
            event.name == TerraMetricKeys.stalledTokenEvent
        }
        let recommendationEvents = allSpanAttributes.filter { event in
            TerraTelemetryClassifier.isRecommendationEvent(
                name: event.name,
                attributes: event.attributes
            )
        }
        let anomalyEvents = allSpanAttributes.filter { event in
            TerraTelemetryClassifier.isAnomalyEvent(
                name: event.name,
                attributes: event.attributes
            )
        }
        let hardwareEvents = allSpanAttributes.filter { event in
            TerraTelemetryClassifier.isHardwareEvent(
                name: event.name,
                attributes: event.attributes
            )
        }

        let runtimeCounts = Dictionary(uniqueKeysWithValues: TraceRuntimeFilter.allCases.map { filter in
            (filter, 0)
        }).merging(
            Dictionary(grouping: traces, by: { $0.detectedRuntime })
                .mapValues { $0.count },
            uniquingKeysWith: { _, newValue in newValue }
        )

        let inferenceSpanCount = max(1, traces.flatMap(\.spans).count)
        let stalledRate = Double(stalledEvents.count) / Double(inferenceSpanCount)
        let promptDecodeSplit = promptDecodeSplitPercent(promptEvalSamples, decodeSamples)

        return DashboardMetrics(
            totalTraces: totalTraces,
            totalSpans: totalSpans,
            averageDuration: averageDuration,
            errorRate: errorRate,
            uniqueAgents: agentNames.count,
            p50Duration: p50,
            p95Duration: p95,
            p99Duration: p99,
            ttftP50: percentile(ttftSamples, 0.50),
            ttftP95: percentile(ttftSamples, 0.95),
            ttftP99: percentile(ttftSamples, 0.99),
            e2eP50: percentile(e2eSamples, 0.50),
            e2eP95: percentile(e2eSamples, 0.95),
            e2eP99: percentile(e2eSamples, 0.99),
            promptEvalP50: percentile(promptEvalSamples, 0.50),
            promptEvalP95: percentile(promptEvalSamples, 0.95),
            promptEvalP99: percentile(promptEvalSamples, 0.99),
            decodeP50: percentile(decodeSamples, 0.50),
            decodeP95: percentile(decodeSamples, 0.95),
            decodeP99: percentile(decodeSamples, 0.99),
            promptDecodeSplit: promptDecodeSplit,
            stalledTokenCount: stalledEvents.count,
            stalledTokenRate: stalledRate,
            recommendationCount: recommendationEvents.count,
            anomalyCount: anomalyEvents.count,
            hardwareTelemetryEventCount: hardwareEvents.count,
            runtimeCounts: runtimeCounts
        )
    }

    private static func percentile(_ sorted: [TimeInterval], _ p: Double) -> TimeInterval {
        let sorted = sorted.sorted()
        guard !sorted.isEmpty else { return 0 }
        let index = p * Double(sorted.count - 1)
        let lower = Int(index)
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = index - Double(lower)
        return sorted[lower] + fraction * (sorted[upper] - sorted[lower])
    }

    private static func promptDecodeSplitPercent(_ prompt: [TimeInterval], _ decode: [TimeInterval]) -> Double {
        let count = min(prompt.count, decode.count)
        guard count > 0 else { return 0 }

        var sumPrompt = 0.0
        var sumDecode = 0.0
        for index in 0..<count {
            sumPrompt += prompt[index]
            sumDecode += decode[index]
        }
        let total = sumPrompt + sumDecode
        guard total > 0 else { return 0 }
        return sumPrompt / total
    }

    private static func attributeToSeconds(_ value: OpenTelemetryApi.AttributeValue?) -> TimeInterval? {
        guard let value else { return nil }
        switch value {
        case .double(let double):
            return max(0, double) / 1000
        case .int(let int):
            return max(0, Double(int)) / 1000
        case .bool(let bool):
            return bool ? 1 : 0
        case .string(let string):
            return Double(string).map { max(0, $0) / 1000 }
        default:
            return nil
        }
    }
}

private enum TerraMetricKeys {
    static let stalledTokenEvent = "terra.anomaly.stalled_token"
}
