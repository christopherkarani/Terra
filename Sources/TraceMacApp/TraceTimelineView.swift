import AppKit
import OpenTelemetryApi
import OpenTelemetrySdk
import TerraTraceKit

final class TraceTimelineView: NSView {
  var onSelectSpan: ((SpanData) -> Void)?

  private var viewModel: TimelineViewModel?
  private var layouts: [SpanLayout] = []
  private var selectedSpanId: SpanId?

  private let rowHeight: CGFloat = 20
  private let rowSpacing: CGFloat = 8
  private let topPadding: CGFloat = 16
  private let leftPadding: CGFloat = 16
  private let rightPadding: CGFloat = 16

  override var isFlipped: Bool { true }

  func update(with viewModel: TimelineViewModel) {
    self.viewModel = viewModel
    self.layouts = []
    self.selectedSpanId = nil
    needsDisplay = true
  }

  func clear() {
    viewModel = nil
    layouts = []
    selectedSpanId = nil
    needsDisplay = true
  }

  func selectSpan(_ span: SpanData) {
    selectedSpanId = span.spanId
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    TraceUI.timelineCanvasColor.setFill()
    dirtyRect.fill()

    guard let viewModel else {
      drawPlaceholder(in: dirtyRect)
      return
    }

    let lanes = viewModel.lanes
    guard !lanes.isEmpty else {
      drawPlaceholder(in: dirtyRect)
      return
    }

    layouts = []

    let totalHeight = topPadding
      + CGFloat(lanes.count) * rowHeight
      + CGFloat(max(0, lanes.count - 1)) * rowSpacing
      + topPadding
    let totalWidth = max(bounds.width, 600)
    let expectedSize = NSSize(width: totalWidth, height: totalHeight)
    if frame.size != expectedSize {
      frame.size = expectedSize
    }

    let availableWidth = totalWidth - leftPadding - rightPadding
    let traceDuration = max(viewModel.trace.duration, 0.001)

    for (laneIndex, lane) in lanes.enumerated() {
      let y = topPadding + CGFloat(laneIndex) * (rowHeight + rowSpacing)
      let laneRect = NSRect(x: leftPadding, y: y - 2, width: availableWidth, height: rowHeight + 4)
      TraceUI.timelineLaneColor.setFill()
      NSBezierPath(roundedRect: laneRect, xRadius: 6, yRadius: 6).fill()

      for item in lane.items {
        let startOffset = item.start.timeIntervalSince(viewModel.trace.startTime)
        let duration = max(item.duration, 0.001)
        let x = leftPadding + CGFloat(startOffset / traceDuration) * availableWidth
        let width = max(2, CGFloat(duration / traceDuration) * availableWidth)
        let rect = NSRect(x: x, y: y, width: width, height: rowHeight)
        layouts.append(SpanLayout(span: item.span, rect: rect, isError: item.isError, isCritical: item.isCritical))

        let fillColor: NSColor
        if item.isError {
          fillColor = .systemRed
        } else if item.isCritical {
          fillColor = .systemOrange
        } else {
          fillColor = .systemBlue
        }

        let barPath = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        fillColor.withAlphaComponent(0.88).setFill()
        barPath.fill()
        TraceUI.timelineStrokeColor.setStroke()
        barPath.lineWidth = 1
        barPath.stroke()

        if item.span.spanId == selectedSpanId {
          NSColor.controlAccentColor.setStroke()
          let strokePath = NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: -1), xRadius: 4, yRadius: 4)
          strokePath.lineWidth = 2
          strokePath.stroke()
        }

        drawLabel(item.span.name, in: rect)
      }
    }
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if let layout = layouts.first(where: { $0.rect.contains(point) }) {
      selectedSpanId = layout.span.spanId
      onSelectSpan?(layout.span)
      needsDisplay = true
    }
  }

  private func drawPlaceholder(in rect: NSRect) {
    let text = "Select a trace to inspect spans"
    let attributes: [NSAttributedString.Key: Any] = [
      .foregroundColor: NSColor.secondaryLabelColor,
      .font: NSFont.systemFont(ofSize: 12, weight: .medium)
    ]
    let size = text.size(withAttributes: attributes)
    let origin = NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2)
    text.draw(at: origin, withAttributes: attributes)
  }

  private func drawLabel(_ text: String, in rect: NSRect) {
    guard rect.width > 52 else { return }
    let attributes: [NSAttributedString.Key: Any] = [
      .foregroundColor: NSColor.white.withAlphaComponent(0.95),
      .font: NSFont.systemFont(ofSize: 10, weight: .semibold)
    ]
    let truncated: String
    if text.count > 26 {
      truncated = String(text.prefix(25)) + "…"
    } else {
      truncated = text
    }
    let insetRect = rect.insetBy(dx: 4, dy: 2)
    truncated.draw(in: insetRect, withAttributes: attributes)
  }
}

private struct SpanLayout {
  let span: SpanData
  let rect: NSRect
  let isError: Bool
  let isCritical: Bool
}
