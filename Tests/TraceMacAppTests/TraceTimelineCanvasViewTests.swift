import Foundation
import OpenTelemetryApi
import Testing
@testable import TraceMacAppUI

@Suite("TraceTimelineCanvasView marker classification and compaction")
struct TraceTimelineCanvasViewTests {
  @Test("Marker kind classifier maps stalled-token events to stall markers")
  func markerKindClassifierDetectsStalls() {
    let kind = TraceTimelineCanvasView.markerKindName(
      eventName: "terra.anomaly.stalled_token",
      attributes: [:]
    )
    #expect(kind == "stall")
  }

  @Test("Marker kind classifier maps recommendation attributes to recommendation markers")
  func markerKindClassifierUsesRecommendationAttributes() {
    let kind = TraceTimelineCanvasView.markerKindName(
      eventName: "provider.event",
      attributes: ["terra.recommendation.kind": .string("thermal_slowdown")]
    )
    #expect(kind == "recommendation")
  }

  @Test("Marker compaction reports coalescing and sampling for high-volume streams")
  func markerCompactionReportsAggregationLevels() {
    let coalescedStats = TraceTimelineCanvasView.markerCompactionStats(
      samples: [
        TimelineMarkerDebugSample(x: 10.2, kind: "decode", spanHex: "a"),
        TimelineMarkerDebugSample(x: 10.8, kind: "decode", spanHex: "a"),
        TimelineMarkerDebugSample(x: 11.1, kind: "decode", spanHex: "a")
      ],
      maxEventMarkers: 10
    )
    #expect(coalescedStats.coalescedCount > 0)
    #expect(coalescedStats.aggregationLevel == "coalesced")

    let highVolumeSamples = (0..<1_500).map { index in
      TimelineMarkerDebugSample(
        x: CGFloat(index) * 3.0,
        kind: "tokenLifecycle",
        spanHex: "\(index)"
      )
    }
    let sampledStats = TraceTimelineCanvasView.markerCompactionStats(
      samples: highVolumeSamples,
      maxEventMarkers: 300
    )
    #expect(sampledStats.aggregationLevel == "sampled")
    #expect(sampledStats.keptCount <= 300)
    #expect(sampledStats.sampledCount > 0)
  }
}
