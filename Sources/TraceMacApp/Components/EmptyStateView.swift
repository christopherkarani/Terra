import SwiftUI

/// A centered empty-state placeholder with an SF Symbol, title, subtitle,
/// and an optional action button.
struct EmptyStateView: View {
    let symbolName: String
    let title: String
    let subtitle: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(DashboardTheme.Colors.textTertiary)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DashboardTheme.Colors.textSecondary)

            Text(subtitle)
                .font(DashboardTheme.Fonts.subtitle)
                .foregroundStyle(DashboardTheme.Colors.textTertiary)

            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(PillButtonStyle())
                    .padding(.top, 4)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
