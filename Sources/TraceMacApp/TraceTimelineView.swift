import AppKit
import OpenTelemetryApi
import OpenTelemetrySdk
import TerraTraceKit

final class TraceTimelineView: NSView, NSAccessibilityGroup {
  var onSelectSpan: ((SpanData) -> Void)?

  private var viewModel: TimelineViewModel?
  private var layouts: [SpanLayout] = []
  private var cachedExpectedSize: NSSize = .zero
  private var selectedSpanId: SpanId?

  private let rowHeight: CGFloat = 20
  private let rowSpacing: CGFloat = 8
  private let topPadding: CGFloat = 16
  private let leftPadding: CGFloat = 16
  private let rightPadding: CGFloat = 16

  override var isFlipped: Bool { true }

  // MARK: - Accessibility

  override func accessibilityRole() -> NSAccessibility.Role? {
    .group
  }

  override func accessibilityChildren() -> [Any]? {
    layouts.map { layout in
      let element = NSAccessibilityElement()
      element.setAccessibilityLabel(layout.span.name)
      element.setAccessibilityRole(.cell)
      let screenRect = window.map { window in
        let windowRect = convert(layout.rect, to: nil)
        return window.convertToScreen(windowRect)
      } ?? layout.rect
      element.setAccessibilityFrame(screenRect)
      element.setAccessibilityParent(self)
      return element
    }
  }

  // MARK: - Public Methods

  func update(with viewModel: TimelineViewModel) {
    self.viewModel = viewModel
    self.selectedSpanId = nil
    rebuildLayouts()
    needsDisplay = true
  }

  func clear() {
    viewModel = nil
    layouts = []
    cachedExpectedSize = .zero
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

    guard viewModel != nil else {
      drawPlaceholder(in: dirtyRect)
      return
    }

    guard !layouts.isEmpty else {
      drawPlaceholder(in: dirtyRect)
      return
    }

    if frame.size != cachedExpectedSize {
      frame.size = cachedExpectedSize
    }

    let availableWidth = cachedExpectedSize.width - leftPadding - rightPadding

    // Draw lane backgrounds
    if let viewModel {
      for (laneIndex, _) in viewModel.lanes.enumerated() {
        let y = topPadding + CGFloat(laneIndex) * (rowHeight + rowSpacing)
        let laneRect = NSRect(x: leftPadding, y: y - 2, width: availableWidth, height: rowHeight + 4)
        TraceUI.timelineLaneColor.setFill()
        NSBezierPath(roundedRect: laneRect, xRadius: 6, yRadius: 6).fill()
      }
    }

    // Draw cached span layouts
    for layout in layouts {
      let fillColor: NSColor
      if layout.isError {
        fillColor = .systemRed
      } else if layout.isCritical {
        fillColor = .systemOrange
      } else {
        fillColor = .systemBlue
      }

      let barPath = NSBezierPath(roundedRect: layout.rect, xRadius: 5, yRadius: 5)
      fillColor.withAlphaComponent(0.88).setFill()
      barPath.fill()
      TraceUI.timelineStrokeColor.setStroke()
      barPath.lineWidth = 1
      barPath.stroke()

      if layout.span.spanId == selectedSpanId {
        NSColor.controlAccentColor.setStroke()
        let strokePath = NSBezierPath(roundedRect: layout.rect.insetBy(dx: -1, dy: -1), xRadius: 4, yRadius: 4)
        strokePath.lineWidth = 2
        strokePath.stroke()
      }

      drawLabel(layout.span.name, in: layout.rect)
    }
  }

  // MARK: - Private Methods

  private func rebuildLayouts() {
    guard let viewModel else {
      layouts = []
      cachedExpectedSize = .zero
      return
    }

    let lanes = viewModel.lanes
    guard !lanes.isEmpty else {
      layouts = []
      cachedExpectedSize = .zero
      return
    }

    var newLayouts: [SpanLayout] = []

    let totalHeight = topPadding
      + CGFloat(lanes.count) * rowHeight
      + CGFloat(max(0, lanes.count - 1)) * rowSpacing
      + topPadding
    let totalWidth = max(bounds.width, 600)
    cachedExpectedSize = NSSize(width: totalWidth, height: totalHeight)

    let availableWidth = totalWidth - leftPadding - rightPadding
    let traceDuration = max(viewModel.trace.duration, 0.001)

    for (laneIndex, lane) in lanes.enumerated() {
      let y = topPadding + CGFloat(laneIndex) * (rowHeight + rowSpacing)
      for item in lane.items {
        let startOffset = item.start.timeIntervalSince(viewModel.trace.startTime)
        let duration = max(item.duration, 0.001)
        let x = leftPadding + CGFloat(startOffset / traceDuration) * availableWidth
        let width = max(2, CGFloat(duration / traceDuration) * availableWidth)
        let rect = NSRect(x: x, y: y, width: width, height: rowHeight)
        newLayouts.append(SpanLayout(span: item.span, rect: rect, isError: item.isError, isCritical: item.isCritical))
      }
    }

    layouts = newLayouts
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
