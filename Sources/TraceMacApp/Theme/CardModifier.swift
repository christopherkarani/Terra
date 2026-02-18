import SwiftUI

/// A view modifier that applies the standard dashboard card style:
/// system background, rounded corners, thin border, and soft shadow.
struct DashboardCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.background)
            .clipShape(.rect(cornerRadius: DashboardTheme.Spacing.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DashboardTheme.Spacing.cornerRadius)
                    .strokeBorder(DashboardTheme.Colors.cardBorder, lineWidth: 1)
            )
            .shadow(
                color: .black.opacity(0.06),
                radius: 2,
                y: 1
            )
    }
}

extension View {
    func dashboardCard() -> some View {
        modifier(DashboardCardModifier())
    }
}
