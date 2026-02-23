import AppKit

enum TraceUI {
  static let contentInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
  static let sectionSpacing: CGFloat = 10
  static let sectionHeaderFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
  static let sectionHeaderColor = NSColor.secondaryLabelColor
  static let subtitleFont = NSFont.systemFont(ofSize: 11, weight: .regular)
  static let subtitleColor = NSColor.tertiaryLabelColor
  static let rowTitleFont = NSFont.systemFont(ofSize: 12, weight: .medium)
  static let rowMetaFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
  static let detailFont = NSFont.systemFont(ofSize: 11, weight: .regular)
  static let surfaceBackgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55)
  static let surfaceBorderColor = NSColor.separatorColor.withAlphaComponent(0.30)
  static let timelineCanvasColor = NSColor.controlBackgroundColor.withAlphaComponent(0.35)
  static let timelineLaneColor = NSColor.separatorColor.withAlphaComponent(0.08)
  static let timelineStrokeColor = NSColor.separatorColor.withAlphaComponent(0.25)

  static func styleSectionHeader(_ label: NSTextField) {
    label.font = sectionHeaderFont
    label.textColor = sectionHeaderColor
  }

  static func styleSubtitle(_ label: NSTextField) {
    label.font = subtitleFont
    label.textColor = subtitleColor
  }

  static func styleSurface(_ view: NSView) {
    view.wantsLayer = true
    guard let layer = view.layer else { return }
    layer.cornerRadius = 10
    layer.borderWidth = 1
    layer.borderColor = surfaceBorderColor.cgColor
    layer.backgroundColor = surfaceBackgroundColor.cgColor
    layer.masksToBounds = true
  }

  static func styleTable(_ table: NSTableView, rowHeight: CGFloat) {
    table.headerView = nil
    table.rowHeight = rowHeight
    table.usesAlternatingRowBackgroundColors = false
    table.backgroundColor = .clear
    table.selectionHighlightStyle = .regular
    table.intercellSpacing = NSSize(width: 0, height: 4)
    table.focusRingType = .none
    table.style = .inset
  }
}

@MainActor
enum TraceFormatter {
  static let durationFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.unitsStyle = .abbreviated
    formatter.maximumUnitCount = 2
    return formatter
  }()

  static let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .medium
    return formatter
  }()

  static func duration(_ interval: TimeInterval) -> String {
    let clamped = max(0, interval)
    if clamped < 1 {
      let milliseconds = Int((clamped * 1000).rounded())
      return "\(milliseconds)ms"
    }
    if let formatted = durationFormatter.string(from: clamped) {
      return formatted
    }
    return String(format: "%.3fs", clamped)
  }

  static func timestamp(_ date: Date) -> String {
    timestampFormatter.string(from: date)
  }

  static func errorRate(_ rate: Double) -> String {
    let percentage = rate * 100
    if percentage == 0 { return "0%" }
    return percentage.formatted(.number.precision(.fractionLength(1))) + "%"
  }

  static func relativeTime(_ date: Date) -> String {
    let interval = -date.timeIntervalSinceNow
    if interval < 0 { return "just now" }
    if interval < 5 { return "just now" }
    if interval < 60 { return "\(Int(interval))s ago" }
    if interval < 3600 { return "\(Int(interval / 60))m ago" }
    if interval < 86400 { return "\(Int(interval / 3600))h ago" }
    return timestamp(date)
  }
}
