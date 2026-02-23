import SwiftUI

/// Solid dark background, white text, 6px radius.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration)
    }
}

private struct PrimaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(DashboardTheme.Colors.accentActive)
            .clipShape(.rect(cornerRadius: DashboardTheme.Spacing.cornerRadius))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.4)
            .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.micro), value: configuration.isPressed)
    }
}

/// 1px border, dark text, hover fill.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonBody(configuration: configuration)
    }
}

private struct SecondaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(DashboardTheme.Colors.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(isHovering && isEnabled ? DashboardTheme.Colors.surfaceHover : .clear)
            .clipShape(.rect(cornerRadius: DashboardTheme.Spacing.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DashboardTheme.Spacing.cornerRadius)
                    .strokeBorder(DashboardTheme.Colors.borderDefault, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.4)
            .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.micro), value: configuration.isPressed)
            .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.micro), value: isHovering)
            .onHover { hovering in isHovering = hovering }
    }
}

/// No border, subtle hover fill, secondary text.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GhostButtonBody(configuration: configuration)
    }
}

private struct GhostButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(DashboardTheme.Colors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(isHovering && isEnabled ? DashboardTheme.Colors.surfaceHover : .clear)
            .clipShape(.rect(cornerRadius: DashboardTheme.Spacing.cornerRadius))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.4)
            .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.micro), value: configuration.isPressed)
            .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.micro), value: isHovering)
            .onHover { hovering in isHovering = hovering }
    }
}

// Legacy aliases for compilation compatibility
typealias PillButtonStyle = PrimaryButtonStyle
typealias AccentButtonStyle = PrimaryButtonStyle
