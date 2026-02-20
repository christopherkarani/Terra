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

  @Test("Marker kind classifier maps lifecycle names consistently")
  func markerKindClassifierUsesLifecycleParityNames() {
    let firstToken = TraceTimelineCanvasView.markerKindName(
      eventName: "terra.first_token",
      attributes: [:]
    )
    #expect(firstToken == "tokenLifecycle")

    let streamLifecycle = TraceTimelineCanvasView.markerKindName(
      eventName: "terra.stream.lifecycle",
      attributes: [:]
    )
    #expect(streamLifecycle == "tokenLifecycle")

    let tokenLifecycle = TraceTimelineCanvasView.markerKindName(
      eventName: "terra.token.lifecycle",
      attributes: [:]
    )
    #expect(tokenLifecycle == "tokenLifecycle")
  }

  @Test("Marker kind classifier maps hardware via name and attributes")
  func markerKindClassifierUsesHardwareParitySignals() {
    let hardwareName = TraceTimelineCanvasView.markerKindName(
      eventName: "terra.hw.sample",
      attributes: [:]
    )
    #expect(hardwareName == "hardware")

    let processName = TraceTimelineCanvasView.markerKindName(
      eventName: "terra.process.sample",
      attributes: [:]
    )
    #expect(processName == "hardware")

    let hardwareAttributes = TraceTimelineCanvasView.markerKindName(
      eventName: "provider.event",
      attributes: ["terra.hw.memory_pressure": .string("warning")]
    )
    #expect(hardwareAttributes == "hardware")
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

  @Test("High-volume mixed marker datasets keep truthful aggregation and kind mapping")
  func mixedMarkerDatasetsRemainStableAtLargeVolume() {
    let samples = (0..<3_000).flatMap { index -> [TimelineMarkerDebugSample] in
      let kind: String
      switch index % 5 {
      case 0:
        kind = "recommendation"
      case 1:
        kind = "anomaly"
      case 2:
        kind = "stall"
      case 3:
        kind = "decode"
      default:
        kind = "tokenLifecycle"
      }
      let baseX = CGFloat(index) * 2.5
      let spanHex = String(format: "%04x", index)
      return [
        TimelineMarkerDebugSample(x: baseX, kind: kind, spanHex: spanHex),
        TimelineMarkerDebugSample(x: baseX + 0.2, kind: kind, spanHex: spanHex),
      ]
    }

    let stats = TraceTimelineCanvasView.markerCompactionStats(
      samples: samples,
      maxEventMarkers: 1_200
    )
    #expect(stats.aggregationLevel == "sampled")
    #expect(stats.keptCount <= 1_200)
    #expect(stats.sampledCount > 0)
    #expect(stats.coalescedCount > 0)

    let anomalyKind = TraceTimelineCanvasView.markerKindName(
      eventName: "provider.event",
      attributes: ["terra.anomaly.kind": .string("stalled_token")]
    )
    #expect(anomalyKind == "anomaly")

    let stallKind = TraceTimelineCanvasView.markerKindName(
      eventName: "terra.anomaly.stalled_token",
      attributes: [:]
    )
    #expect(stallKind == "stall" || stallKind == "anomaly")
  }
}
