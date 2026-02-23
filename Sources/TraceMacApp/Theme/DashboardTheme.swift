import SwiftUI
import AppKit

// Disambiguate SwiftUI.View from OpenTelemetryApi.View (metrics)
// which enters scope when any file imports OpenTelemetrySdk/OpenTelemetryApi.
typealias View = SwiftUI.View
typealias ViewBuilder = SwiftUI.ViewBuilder

// MARK: - Adaptive Color Helper

extension Color {
    /// Creates an adaptive color that responds to the system's Light/Dark Mode appearance.
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
    }
}

/// SaaS-grade design tokens — Swiss-industrial precision.
/// Adaptive for Light and Dark Mode. Color reserved for status + flow graph nodes.
enum DashboardTheme {

    // MARK: - Colors

    enum Colors {
        // Backgrounds
        static let windowBackground = Color(
            light: Color(red: 1, green: 1, blue: 1),                                      // #FFFFFF
            dark:  Color(red: 0.051, green: 0.059, blue: 0.078)                            // #0D0F14
        )
        static let sidebarBackground = Color(
            light: Color(red: 0.98, green: 0.98, blue: 0.98),                              // #FAFAFA
            dark:  Color(red: 0.067, green: 0.075, blue: 0.094)                            // #111318
        )
        static let surfaceRaised = Color(
            light: Color(red: 0.969, green: 0.969, blue: 0.969),                           // #F7F7F7
            dark:  Color(red: 0.102, green: 0.114, blue: 0.141)                            // #1A1D24
        )
        static let surfaceHover = Color(
            light: Color(red: 0.949, green: 0.949, blue: 0.949),                           // #F2F2F2
            dark:  Color(red: 0.133, green: 0.149, blue: 0.180)                            // #22262E
        )
        static let surfaceActive = Color(
            light: Color(red: 0.929, green: 0.929, blue: 0.929),                           // #EDEDED
            dark:  Color(red: 0.165, green: 0.184, blue: 0.220)                            // #2A2F38
        )

        // Borders
        static let borderDefault = Color(
            light: Color(red: 0.898, green: 0.898, blue: 0.898),                           // #E5E5E5
            dark:  Color(red: 0.165, green: 0.184, blue: 0.220)                            // #2A2F38
        )
        static let borderSubtle = Color(
            light: Color(red: 0.941, green: 0.941, blue: 0.941),                           // #F0F0F0
            dark:  Color(red: 0.118, green: 0.129, blue: 0.157)                            // #1E2128
        )
        static let borderStrong = Color(
            light: Color(red: 0.820, green: 0.820, blue: 0.820),                           // #D1D1D1
            dark:  Color(red: 0.227, green: 0.251, blue: 0.314)                            // #3A4050
        )

        // Text hierarchy
        static let textPrimary = Color(
            light: Color(red: 0.039, green: 0.039, blue: 0.039),                           // #0A0A0A
            dark:  Color(red: 0.941, green: 0.941, blue: 0.941)                            // #F0F0F0
        )
        static let textSecondary = Color(
            light: Color(red: 0.333, green: 0.333, blue: 0.333),                           // #555555
            dark:  Color(red: 0.627, green: 0.659, blue: 0.722)                            // #A0A8B8
        )
        static let textTertiary = Color(
            light: Color(red: 0.541, green: 0.541, blue: 0.541),                           // #8A8A8A
            dark:  Color(red: 0.420, green: 0.447, blue: 0.502)                            // #6B7280
        )
        static let textQuaternary = Color(
            light: Color(red: 0.627, green: 0.627, blue: 0.627),                           // #A0A0A0 (bumped from #B5B5B5 for AA compliance)
            dark:  Color(red: 0.294, green: 0.322, blue: 0.376)                            // #4B5260
        )

        // Semantic accents — vivid, mode-invariant
        static let accentError = Color(red: 0.937, green: 0.267, blue: 0.267)              // #EF4444
        static let accentWarning = Color(red: 0.961, green: 0.620, blue: 0.043)            // #F59E0B
        static let accentSuccess = Color(red: 0.133, green: 0.773, blue: 0.369)            // #22C55E
        static let accentActive = Color(red: 0.486, green: 0.227, blue: 0.929)             // #7C3AED violet

        // Flow graph node type accents — ONLY vivid colors in the UI (same for both modes)
        static let nodeAgent = Color(red: 0.486, green: 0.227, blue: 0.929)                // #7C3AED
        static let nodeInference = Color(red: 0.145, green: 0.388, blue: 0.922)            // #2563EB
        static let nodeTool = Color(red: 0.918, green: 0.345, blue: 0.047)                 // #EA580C
        static let nodeStage = Color(red: 0.420, green: 0.447, blue: 0.498)                // #6B7280
        static let nodeEmbedding = Color(red: 0.031, green: 0.569, blue: 0.698)            // #0891B2
        static let nodeSafety = Color(red: 0.086, green: 0.639, blue: 0.290)               // #16A34A

        // Semantic backgrounds — 6% opacity for badge fills (12% in dark for visibility)
        static let errorBackground = Color(
            light: accentError.opacity(0.06),
            dark:  accentError.opacity(0.12)
        )
        static let warningBackground = Color(
            light: accentWarning.opacity(0.06),
            dark:  accentWarning.opacity(0.12)
        )
        static let successBackground = Color(
            light: accentSuccess.opacity(0.06),
            dark:  accentSuccess.opacity(0.12)
        )
        static let activeBackground = Color(
            light: accentActive.opacity(0.06),
            dark:  accentActive.opacity(0.12)
        )

        // Event category badge colors
        static let categoryLifecycle = Color(red: 0.486, green: 0.227, blue: 0.929)       // #7C3AED violet
        static let categoryPolicy = Color(red: 0.231, green: 0.510, blue: 0.965)          // #3B82F6 blue
        static let categoryHardware = Color(red: 0.024, green: 0.714, blue: 0.831)        // #06B6D4 teal
        static let categoryRecommendations = Color(red: 0.133, green: 0.773, blue: 0.369) // #22C55E green
        static let categoryAnomalies = Color(red: 0.937, green: 0.267, blue: 0.267)       // #EF4444 red

        // Chart line colors
        static let chartGPU = Color(red: 0.655, green: 0.545, blue: 0.980)               // #A78BFA light violet
        static let chartMemory = Color(red: 0.176, green: 0.831, blue: 0.749)            // #2DD4BF teal

        // Span colors — 6-step palette hashed by name
        // Light mode: grayscale. Dark mode: vivid observability palette.
        static let spanGrayscale: [Color] = [
            Color(light: Color(red: 0.176, green: 0.176, blue: 0.176),                     // #2D2D2D
                  dark:  Color(red: 0.231, green: 0.510, blue: 0.965)),                    // #3B82F6 blue
            Color(light: Color(red: 0.286, green: 0.286, blue: 0.286),                     // #494949
                  dark:  Color(red: 0.486, green: 0.227, blue: 0.929)),                    // #7C3AED violet
            Color(light: Color(red: 0.400, green: 0.400, blue: 0.400),                     // #666666
                  dark:  Color(red: 0.024, green: 0.714, blue: 0.831)),                    // #06B6D4 teal
            Color(light: Color(red: 0.502, green: 0.502, blue: 0.502),                     // #808080
                  dark:  Color(red: 0.961, green: 0.620, blue: 0.043)),                    // #F59E0B amber
            Color(light: Color(red: 0.557, green: 0.557, blue: 0.557),                     // #8E8E8E
                  dark:  Color(red: 0.133, green: 0.773, blue: 0.369)),                    // #22C55E green
            Color(light: Color(red: 0.627, green: 0.627, blue: 0.627),                     // #A0A0A0
                  dark:  Color(red: 0.925, green: 0.282, blue: 0.600)),                    // #EC4899 pink
        ]

        // Legacy aliases (deprecated — use new tokens)
        @available(*, deprecated, renamed: "windowBackground")
        static let cardBackground = windowBackground
        @available(*, deprecated, renamed: "borderDefault")
        static let cardBorder = borderDefault
        @available(*, deprecated, renamed: "surfaceRaised")
        static let surfaceBackground = surfaceRaised
        @available(*, deprecated, renamed: "accentActive")
        static let accentNormal = accentActive
        @available(*, deprecated, renamed: "surfaceRaised")
        static let surfaceElevated = surfaceRaised
        @available(*, deprecated, renamed: "accentActive")
        static var accentGlow: Color { accentActive.opacity(0.25) }

        static let serviceColors: [Color] = spanGrayscale

        static func serviceColor(for name: String) -> Color {
            let hash = name.utf8.reduce(UInt(0)) { ($0 &+ UInt($1)) &* 31 }
            return spanGrayscale[Int(hash % UInt(spanGrayscale.count))]
        }
    }

    // MARK: - Fonts

    enum Fonts {
        // Display
        static let displayLarge = Font.system(size: 24, weight: .semibold)
        static let displayMedium = Font.system(size: 20, weight: .semibold)

        // KPI
        static let kpiValue = Font.system(size: 20, weight: .semibold)
        static let kpiLabel = Font.system(size: 11, weight: .medium)
        static let kpiUnit = Font.system(size: 11, weight: .medium).monospaced()

        // Section headers
        static let sectionHeader = Font.system(size: 11, weight: .semibold).uppercaseSmallCaps()

        // Body
        static let rowTitle = Font.system(size: 13, weight: .medium)
        static let rowSubtitle = Font.system(size: 12, weight: .regular)
        static let rowMeta = Font.system(size: 11, weight: .regular).monospacedDigit()

        // Code
        static let codeLarge = Font.system(size: 11, design: .monospaced)
        static let codeSmall = Font.system(size: 10, design: .monospaced)

        // Badges
        static let badge = Font.system(size: 10, weight: .medium)

        // Legacy aliases
        static let detail = Font.system(size: 11)
        static let subtitle = Font.system(size: 12, weight: .regular)
    }

    // MARK: - Spacing (4px base grid)

    enum Spacing {
        static let xs: CGFloat = 2
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 24

        // Card / section
        static let cardPadding: CGFloat = 12
        static let sectionSpacing: CGFloat = 16
        static let cornerRadius: CGFloat = 6
        static let cornerRadiusSmall: CGFloat = 4
        static let cornerRadiusLarge: CGFloat = 8

        // Legacy aliases
        static let contentPadding: CGFloat = 12
        static let cardGap: CGFloat = 12
    }

    // MARK: - Shadows

    enum Shadows {
        static let sm = (color: Color.black.opacity(0.3), radius: CGFloat(2), y: CGFloat(1))
        static let md = (color: Color.black.opacity(0.4), radius: CGFloat(4), y: CGFloat(2))
        static let lg = (color: Color.black.opacity(0.6), radius: CGFloat(8), y: CGFloat(4))
    }

    // MARK: - Animation

    enum Animation {
        /// Hover states, badge transitions
        static let micro = SwiftUI.Animation.easeOut(duration: 0.10)
        /// Tab switches, panel reveals
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.2)
        /// Node positioning, layout shifts
        static let smooth = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.85)
        /// Staggered node reveals (flow graph load)
        static let entrance = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.75)
        /// Running/streaming node status dot
        static let pulse = SwiftUI.Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)

        // Legacy alias
        static let quick = SwiftUI.Animation.easeOut(duration: 0.10)

        /// Whether the user has enabled Reduce Motion in System Settings.
        static var prefersReducedMotion: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }

        /// Accessible animation wrapper — respects Reduce Motion preference.
        /// When Reduce Motion is enabled, executes the body immediately without animation.
        @discardableResult
        static func withAccessibleAnimation<Result>(
            _ animation: SwiftUI.Animation? = standard,
            _ body: () throws -> Result
        ) rethrows -> Result {
            if prefersReducedMotion {
                return try body()
            } else {
                return try withAnimation(animation, body)
            }
        }

        /// Returns `nil` when Reduce Motion is enabled, otherwise returns the given animation.
        /// Use with `.animation()` view modifiers: `.animation(Animation.accessible(.standard), value:)`
        static func accessible(_ animation: SwiftUI.Animation?) -> SwiftUI.Animation? {
            prefersReducedMotion ? nil : animation
        }
    }

    // MARK: - Convenience Accessors (preserve compilation)

    static var cardBackground: Color { Colors.windowBackground }
    static var cardBorder: Color { Colors.borderDefault }
    static var surfaceBackground: Color { Colors.surfaceRaised }
    static var accentNormal: Color { Colors.accentActive }
    static var accentError: Color { Colors.accentError }
    static var accentWarning: Color { Colors.accentWarning }
    static var accentSuccess: Color { Colors.accentSuccess }
    static var textPrimary: Color { Colors.textPrimary }
    static var textSecondary: Color { Colors.textSecondary }
    static var textTertiary: Color { Colors.textTertiary }
    static var accentGlow: Color { Colors.accentActive.opacity(0.25) }
    static var surfaceElevated: Color { Colors.surfaceRaised }

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
