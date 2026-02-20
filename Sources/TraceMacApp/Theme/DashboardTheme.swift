import SwiftUI

// Disambiguate SwiftUI.View from OpenTelemetryApi.View (metrics)
// which enters scope when any file imports OpenTelemetrySdk/OpenTelemetryApi.
typealias View = SwiftUI.View
typealias ViewBuilder = SwiftUI.ViewBuilder

/// Stripe-inspired design tokens for the TraceMacApp dashboard.
enum DashboardTheme {

    // MARK: - Colors

    enum Colors {
        static let cardBackground = Color(.windowBackgroundColor)
        static let cardBorder = Color(.separatorColor).opacity(0.3)
        static let surfaceBackground = Color(.controlBackgroundColor).opacity(0.55)
        static let accentNormal  = Color(red: 0.18, green: 0.55, blue: 0.53)   // Deep teal
        static let accentError   = Color(red: 0.84, green: 0.24, blue: 0.22)   // Terracotta red
        static let accentWarning = Color(red: 0.85, green: 0.58, blue: 0.20)   // Amber
        static let accentSuccess = Color(red: 0.30, green: 0.60, blue: 0.36)   // Sage green
        static let accentGlow    = accentNormal.opacity(0.25)
        static let surfaceElevated = Color(.controlBackgroundColor).opacity(0.75)
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color(nsColor: .tertiaryLabelColor)

        static let serviceColors: [Color] = [
            Color(red: 0.18, green: 0.55, blue: 0.53),  // Teal
            Color(red: 0.55, green: 0.35, blue: 0.65),  // Plum
            Color(red: 0.20, green: 0.48, blue: 0.65),  // Steel blue
            Color(red: 0.60, green: 0.42, blue: 0.24),  // Copper
            Color(red: 0.35, green: 0.55, blue: 0.35),  // Forest
            Color(red: 0.58, green: 0.28, blue: 0.45),  // Mulberry
            Color(red: 0.40, green: 0.50, blue: 0.55),  // Slate
            Color(red: 0.65, green: 0.48, blue: 0.18),  // Gold
        ]

        static func serviceColor(for name: String) -> Color {
            let hash = name.utf8.reduce(UInt(0)) { ($0 &+ UInt($1)) &* 31 }
            return serviceColors[Int(hash) % serviceColors.count]
        }
    }

    // MARK: - Fonts

    enum Fonts {
        static let kpiValue = Font.system(size: 28, weight: .bold)
        static let kpiLabel = Font.system(size: 12, weight: .medium)
        static let sectionHeader = Font.system(size: 11, weight: .semibold)
        static let rowTitle = Font.system(size: 12, weight: .medium)
        static let rowMeta = Font.system(size: 11, weight: .regular).monospacedDigit()
        static let detail = Font.system(size: 11)
        static let subtitle = Font.system(size: 11)
    }

    // MARK: - Spacing

    enum Spacing {
        static let contentPadding: CGFloat = 14
        static let cardGap: CGFloat = 12
        static let sectionSpacing: CGFloat = 10
        static let cornerRadius: CGFloat = 10
    }

    // MARK: - Animation

    enum Animation {
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.15)
    }

    // MARK: - Convenience Accessors

    static var cardBackground: Color { Colors.cardBackground }
    static var cardBorder: Color { Colors.cardBorder }
    static var surfaceBackground: Color { Colors.surfaceBackground }
    static var accentNormal: Color { Colors.accentNormal }
    static var accentError: Color { Colors.accentError }
    static var accentWarning: Color { Colors.accentWarning }
    static var accentSuccess: Color { Colors.accentSuccess }
    static var textPrimary: Color { Colors.textPrimary }
    static var textSecondary: Color { Colors.textSecondary }
    static var textTertiary: Color { Colors.textTertiary }
    static var accentGlow: Color { Colors.accentGlow }
    static var surfaceElevated: Color { Colors.surfaceElevated }

    static var kpiValue: Font { Fonts.kpiValue }
    static var kpiLabel: Font { Fonts.kpiLabel }
    static var sectionHeader: Font { Fonts.sectionHeader }
    static var rowTitle: Font { Fonts.rowTitle }
    static var rowMeta: Font { Fonts.rowMeta }
    static var detail: Font { Fonts.detail }
    static var subtitle: Font { Fonts.subtitle }

    static var contentPadding: CGFloat { Spacing.contentPadding }
    static var cardGap: CGFloat { Spacing.cardGap }
    static var sectionSpacing: CGFloat { Spacing.sectionSpacing }
    static var cornerRadius: CGFloat { Spacing.cornerRadius }

    static var standard: SwiftUI.Animation { Animation.standard }
    static var quick: SwiftUI.Animation { Animation.quick }
}
