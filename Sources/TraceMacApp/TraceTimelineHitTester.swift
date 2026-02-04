import CoreGraphics
import TerraTraceKit

struct TraceTimelineHitTester {
  static func spanID(
    at point: CGPoint,
    in bounds: CGRect,
    items: [TraceTimelineModel.Item]
  ) -> SpanID? {
    guard !items.isEmpty else { return nil }

    let horizontalPadding = TraceUIStyle.Spacing.large
    let verticalPadding = TraceUIStyle.Spacing.large
    let rowHeight = TraceUIStyle.Sizing.timelineRowHeight
    let rowSpacing = TraceUIStyle.Sizing.timelineRowSpacing
    let minimumBarWidth = TraceUIStyle.Sizing.timelineMinimumBarWidth

    let contentRect = bounds.insetBy(dx: horizontalPadding, dy: verticalPadding)
    guard contentRect.width > 0, contentRect.height > 0 else { return nil }

    let rowStride = rowHeight + rowSpacing
    let contentWidth = contentRect.width
    var y = contentRect.minY

    for item in items {
      if y + rowHeight > contentRect.maxY { break }
      let rowRect = CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: rowHeight)
      if rowRect.contains(point) {
        let start = max(0, min(1, item.normalizedStart))
        let end = min(1, max(start, start + max(0, item.normalizedDuration)))
        var width = (end - start) * contentWidth
        if width < minimumBarWidth {
          width = min(minimumBarWidth, contentWidth)
        }

        let x = contentRect.minX + (start * contentWidth)
        let maxWidth = max(0, contentRect.maxX - x)
        let barWidth = min(width, maxWidth)
        let barRect = CGRect(x: x, y: y, width: barWidth, height: rowHeight)
        if barRect.contains(point) {
          return item.spanID
        }
        return nil
      }
      y += rowStride
    }
    return nil
  }
}
