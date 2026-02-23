import SwiftUI
import TerraTraceKit
import OpenTelemetrySdk

/// Real-time updates + animation choreography for the flow graph.
/// Diffs current trace against previous span set.
/// Animation queue: nodeAppear (staggered by depth), edgeAppear (progressive trim),
/// nodeUpdate (status change), layoutShift (smooth spring).
@Observable
@MainActor
final class FlowGraphStreamingController {
    var isAutoFollowing = true

    private weak var flowModel: FlowGraphModel?
    private var previousSpanIDs: Set<String> = []

    init(flowModel: FlowGraphModel) {
        self.flowModel = flowModel
    }

    /// Diff current trace against previous span set and apply incremental updates.
    /// Node entrance: staggered by depth — root at 0ms, children at +80ms each level.
    /// Scale from 0.85 + opacity 0 → 1.0 using entrance spring.
    func update(with trace: Trace) {
        guard let flowModel else { return }

        let currentSpanIDs = Set(trace.spans.map { $0.spanId.hexString })
        let newSpanIDs = currentSpanIDs.subtracting(previousSpanIDs)
        let existingSpanIDs = currentSpanIDs.intersection(previousSpanIDs)

        // Add new spans with staggered animation
        let newSpans = trace.spans.filter { newSpanIDs.contains($0.spanId.hexString) }
            .sorted { $0.startTime < $1.startTime }

        for (index, span) in newSpans.enumerated() {
            let delay = Double(index) * 0.08 // +80ms per depth level
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.entrance) {
                    flowModel.addSpan(span)
                }
            }
        }

        // Update existing spans (status + phase changes)
        let existingSpans = trace.spans.filter { existingSpanIDs.contains($0.spanId.hexString) }
        for span in existingSpans {
            updateSpan(span)
        }

        previousSpanIDs = currentSpanIDs
    }

    /// Reset tracking state.
    func reset() {
        previousSpanIDs = []
        isAutoFollowing = true
    }

    // MARK: - Phase-Driven Updates

    private func updateSpan(_ span: SpanData) {
        guard let flowModel, let node = flowModel.node(for: span.spanId.hexString) else { return }

        let newPhase = Self.computePhase(from: span)
        if newPhase > node.revealPhase {
            DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.entrance) {
                node.revealPhase = newPhase
                node.liveOutputTokens = Self.extractOutputTokens(from: span)
                node.liveTPS = Self.extractTPS(from: span)
            }
            flowModel.rebuildLayout()
        }

        let newStatus = Self.computeStatus(from: span)
        if newStatus != node.status {
            DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                node.status = newStatus
            }
        }
    }

    static func computePhase(from span: SpanData) -> RevealPhase {
        let outputTok = FlowGraphNode.intAttribute(span.attributes["gen_ai.usage.output_tokens"])
        if span.endTime > span.startTime {
            return .complete
        } else if outputTok > 0 {
            return .streaming
        } else {
            return .started
        }
    }

    static func computeStatus(from span: SpanData) -> FlowNodeStatus {
        if span.status.isError {
            return .error
        } else if span.endTime > span.startTime {
            return .completed
        } else {
            return .running
        }
    }

    static func extractOutputTokens(from span: SpanData) -> Int {
        FlowGraphNode.intAttribute(span.attributes["gen_ai.usage.output_tokens"])
    }

    static func extractTPS(from span: SpanData) -> Double? {
        FlowGraphNode.doubleAttribute(span.attributes["terra.stream.tokens_per_second"])
    }
}
