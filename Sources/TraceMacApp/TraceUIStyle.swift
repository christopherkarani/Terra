import AppKit
import TerraTraceKit

@MainActor
enum TraceUIStyle {
    enum Typography {
        static let title = NSFont.systemFont(ofSize: 18, weight: .semibold)
        static let subtitle = NSFont.systemFont(ofSize: 12, weight: .regular)
        static let body = NSFont.systemFont(ofSize: 12, weight: .regular)
        static let mono = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        static let emptyTitle = NSFont.systemFont(ofSize: 13, weight: .semibold)
        static let emptySubtitle = NSFont.systemFont(ofSize: 12, weight: .regular)
    }

    enum Spacing {
        static let xSmall: CGFloat = DashboardTheme.Spacing.xs
        static let small: CGFloat = DashboardTheme.Spacing.md
        static let medium: CGFloat = DashboardTheme.Spacing.lg
        static let large: CGFloat = DashboardTheme.Spacing.xl
        static let xLarge: CGFloat = DashboardTheme.Spacing.xxl
    }

    enum Sizing {
        static let listRowHeight: CGFloat = 28
        static let listStatusDot: CGFloat = 6
        static let timelineRowHeight: CGFloat = 14
        static let timelineRowSpacing: CGFloat = 8
        static let timelineMinimumBarWidth: CGFloat = 2
    }

    enum Colors {
        // Adaptive NSColors that respond to Light/Dark Mode
        static let primaryText = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(red: 0.941, green: 0.941, blue: 0.941, alpha: 1)    // #F0F0F0
                : NSColor(red: 0.039, green: 0.039, blue: 0.039, alpha: 1)    // #0A0A0A
        }
        static let secondaryText = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(red: 0.627, green: 0.659, blue: 0.722, alpha: 1)    // #A0A8B8
                : NSColor(red: 0.333, green: 0.333, blue: 0.333, alpha: 1)    // #555555
        }
        static let tertiaryText = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(red: 0.420, green: 0.447, blue: 0.502, alpha: 1)    // #6B7280
                : NSColor(red: 0.541, green: 0.541, blue: 0.541, alpha: 1)    // #8A8A8A
        }
        static let listBackground = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(red: 0.051, green: 0.059, blue: 0.078, alpha: 1)    // #0D0F14
                : NSColor.white
        }
        static let timelineBackground = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(red: 0.051, green: 0.059, blue: 0.078, alpha: 1)    // #0D0F14
                : NSColor.white
        }
        static let timelineRow = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(red: 0.102, green: 0.114, blue: 0.141, alpha: 1)    // #1A1D24
                : NSColor(red: 0.969, green: 0.969, blue: 0.969, alpha: 1)    // #F7F7F7
        }
        static let timelineRowAlternate = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(red: 0.067, green: 0.075, blue: 0.094, alpha: 1)    // #111318
                : NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)       // #FAFAFA
        }
        static let loadingBackdrop = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(red: 0.051, green: 0.059, blue: 0.078, alpha: 0.9)  // #0D0F14 @ 90%
                : NSColor.white.withAlphaComponent(0.9)
        }

        static func status(_ status: StatusCode) -> NSColor {
            switch status {
            case .ok:
                return NSColor(red: 0.133, green: 0.773, blue: 0.369, alpha: 1) // #22C55E
            case .error:
                return NSColor(red: 0.937, green: 0.267, blue: 0.267, alpha: 1) // #EF4444
            case .unset:
                return NSColor(red: 0.961, green: 0.620, blue: 0.043, alpha: 1) // #F59E0B
            }
        }

        static func statusFill(_ status: StatusCode) -> NSColor {
            Colors.status(status).withAlphaComponent(0.75)
        }
    }
}
