import AppKit
import TerraTraceKit

@MainActor
enum TraceUIStyle {
  enum Typography {
    static let title = NSFont.systemFont(ofSize: 18, weight: .semibold)
    static let subtitle = NSFont.systemFont(ofSize: 12, weight: .regular)
    static let body = NSFont.systemFont(ofSize: 12, weight: .regular)
    static let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    static let emptyTitle = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let emptySubtitle = NSFont.systemFont(ofSize: 12, weight: .regular)
  }

  enum Spacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 20
  }

  enum Sizing {
    static let listRowHeight: CGFloat = 28
    static let listStatusDot: CGFloat = 8
    static let timelineRowHeight: CGFloat = 14
    static let timelineRowSpacing: CGFloat = 8
    static let timelineMinimumBarWidth: CGFloat = 2
  }

  enum Colors {
    static let primaryText = NSColor.labelColor
    static let secondaryText = NSColor.secondaryLabelColor
    static let tertiaryText = NSColor.tertiaryLabelColor
    static let listBackground = NSColor.textBackgroundColor
    static let timelineBackground = NSColor.windowBackgroundColor
    static let timelineRow = NSColor.controlBackgroundColor.withAlphaComponent(0.7)
    static let timelineRowAlternate = NSColor.controlBackgroundColor.withAlphaComponent(0.45)
    static let loadingBackdrop = NSColor.windowBackgroundColor.withAlphaComponent(0.9)

    static func status(_ status: StatusCode) -> NSColor {
      switch status {
      case .ok:
        return NSColor.systemGreen
      case .error:
        return NSColor.systemRed
      case .unset:
        return NSColor.systemOrange
      }
    }

    static func statusFill(_ status: StatusCode) -> NSColor {
      Colors.status(status).withAlphaComponent(0.75)
    }
  }
}
