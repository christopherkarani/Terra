import SwiftUI

/// Dashboard card style: white background, 6px radius, 1px border.
/// No shadows, no materials, no gradients.
struct DashboardCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(DashboardTheme.Colors.windowBackground)
            .clipShape(.rect(cornerRadius: DashboardTheme.Spacing.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DashboardTheme.Spacing.cornerRadius)
                    .strokeBorder(DashboardTheme.Colors.borderDefault, lineWidth: 1)
            )
    }
}

extension View {
    func dashboardCard() -> some View {
        modifier(DashboardCardModifier())
    }
}
