import AppKit

@MainActor
final class TraceTimelineView: NSView {
  private enum Constants {
    static let rowHeight: CGFloat = TraceUIStyle.Sizing.timelineRowHeight
    static let rowSpacing: CGFloat = TraceUIStyle.Sizing.timelineRowSpacing
    static let horizontalPadding: CGFloat = TraceUIStyle.Spacing.large
    static let verticalPadding: CGFloat = TraceUIStyle.Spacing.large
    static let minimumBarWidth: CGFloat = TraceUIStyle.Sizing.timelineMinimumBarWidth
  }

  private var items: [TraceTimelineModel.Item] = []
  private let backgroundColor = TraceUIStyle.Colors.timelineBackground

  override var isFlipped: Bool {
    true
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    setAccessibilityLabel("Trace timeline")
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    wantsLayer = true
    setAccessibilityLabel("Trace timeline")
  }

  func update(model: TraceTimelineModel?) {
    precondition(Thread.isMainThread)
    if let model {
      items = model.items
    } else {
      items.removeAll(keepingCapacity: true)
    }
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    precondition(Thread.isMainThread)
    guard let context = NSGraphicsContext.current?.cgContext else { return }

    context.setFillColor(backgroundColor.cgColor)
    context.fill(bounds)

    guard !items.isEmpty else { return }

    let contentRect = bounds.insetBy(dx: Constants.horizontalPadding, dy: Constants.verticalPadding)
    guard contentRect.width > 0, contentRect.height > 0 else { return }

    let rowStride = Constants.rowHeight + Constants.rowSpacing
    let contentWidth = contentRect.width
    var y = contentRect.minY
    var index = 0

    for item in items {
      if y + Constants.rowHeight > contentRect.maxY { break }

      let rowRect = CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: Constants.rowHeight)
      let rowColor = index.isMultiple(of: 2)
        ? TraceUIStyle.Colors.timelineRow
        : TraceUIStyle.Colors.timelineRowAlternate
      context.setFillColor(rowColor.cgColor)
      context.fill(rowRect)

      let start = max(0, min(1, item.normalizedStart))
      let end = min(1, max(start, start + max(0, item.normalizedDuration)))
      var width = (end - start) * contentWidth
      if width < Constants.minimumBarWidth {
        width = min(Constants.minimumBarWidth, contentWidth)
      }

      let x = contentRect.minX + (start * contentWidth)
      let maxWidth = max(0, contentRect.maxX - x)
      let barWidth = min(width, maxWidth)

      if barWidth > 0 {
        let barRect = CGRect(x: x, y: y, width: barWidth, height: Constants.rowHeight)
        let barColor = TraceUIStyle.Colors.statusFill(item.status)
        context.setFillColor(barColor.cgColor)
        context.fill(barRect)
      }

      y += rowStride
      index += 1
    }
  }
}
