import Foundation
import TerraTraceKit

struct DashboardMetrics {
    let totalTraces: Int
    let totalSpans: Int
    let averageDuration: TimeInterval
    let errorRate: Double
    let uniqueAgents: Int
    let p50Duration: TimeInterval
    let p95Duration: TimeInterval
    let p99Duration: TimeInterval
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

        return DashboardMetrics(
            totalTraces: totalTraces,
            totalSpans: totalSpans,
            averageDuration: averageDuration,
            errorRate: errorRate,
            uniqueAgents: agentNames.count,
            p50Duration: p50,
            p95Duration: p95,
            p99Duration: p99
        )
    }

    private static func percentile(_ sorted: [TimeInterval], _ p: Double) -> TimeInterval {
        guard !sorted.isEmpty else { return 0 }
        let index = p * Double(sorted.count - 1)
        let lower = Int(index)
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = index - Double(lower)
        return sorted[lower] + fraction * (sorted[upper] - sorted[lower])
    }
}
