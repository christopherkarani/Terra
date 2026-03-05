import Foundation
import OpenTelemetrySdk

/// Timeline layout data for a single span.
struct SpanTimelineItem: Equatable {
  /// The underlying span.
  let span: SpanData
  /// Span start time.
  let start: Date
  /// Span end time.
  let end: Date
  /// True if the span has error status.
  let isError: Bool
  /// True if the span is considered long-running.
  let isCritical: Bool

  /// Span duration in seconds.
  var duration: TimeInterval {
    end.timeIntervalSince(start)
  }
}

/// A non-overlapping lane of timeline items.
struct TimelineLane: Equatable {
  /// Items assigned to this lane.
  let items: [SpanTimelineItem]

  /// Creates a lane with ordered timeline items.
  init(items: [SpanTimelineItem]) {
    self.items = items
  }
}

/// View model that packs spans into non-overlapping timeline lanes.
@MainActor
final class TimelineViewModel {
  /// Duration threshold used to flag critical spans.
  static let criticalDurationThreshold: TimeInterval = 5

  /// The trace being visualized.
  let trace: Trace
  /// Computed lanes for timeline rendering.
  private(set) var lanes: [TimelineLane]

  /// Creates a timeline view model for a trace.
  init(trace: Trace) {
    self.trace = trace
    self.lanes = TimelineViewModel.buildLanes(from: trace)
  }

  private static func buildLanes(from trace: Trace) -> [TimelineLane] {
    let items = trace.orderedSpans.map { span in
      SpanTimelineItem(
        span: span,
        start: span.startTime,
        end: span.endTime,
        isError: span.status.isError,
        isCritical: span.endTime.timeIntervalSince(span.startTime) >= criticalDurationThreshold
      )
    }

    var lanes = [[SpanTimelineItem]]()
    for item in items {
      if let index = lanes.firstIndex(where: { lane in
        guard let last = lane.last else { return true }
        return last.end <= item.start
      }) {
        lanes[index].append(item)
      } else {
        lanes.append([item])
      }
    }

    return lanes.map { TimelineLane(items: $0) }
  }
}
