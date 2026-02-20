import SwiftUI

/// A capsule-shaped button with accent fill and white text.
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(DashboardTheme.Colors.accentNormal)
            .clipShape(.capsule)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(DashboardTheme.Animation.quick, value: configuration.isPressed)
    }
}

/// A transparent button with accent text and a subtle border on hover.
struct GhostButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(DashboardTheme.Colors.accentNormal)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .strokeBorder(
                        DashboardTheme.Colors.accentNormal.opacity(isHovering ? 0.4 : 0),
                        lineWidth: 1
                    )
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(DashboardTheme.Animation.quick, value: configuration.isPressed)
            .animation(DashboardTheme.Animation.quick, value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

/// A filled accent button with larger padding for primary actions.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(DashboardTheme.Colors.accentNormal)
            .clipShape(.rect(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(DashboardTheme.Animation.quick, value: configuration.isPressed)
    }
}
