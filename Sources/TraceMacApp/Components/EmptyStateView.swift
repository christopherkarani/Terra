import SwiftUI

/// A centered empty-state placeholder with an SF Symbol, title, subtitle,
/// and an optional action button.
struct EmptyStateView: View {
    let symbolName: String
    let title: String
    let subtitle: String
    var buttonTitle: String? = nil
    var secondaryButtonTitle: String? = nil
    var action: (() -> Void)? = nil
    var secondaryAction: (() -> Void)? = nil

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(DashboardTheme.Colors.borderStrong)
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DashboardTheme.Colors.textSecondary)

            Text(subtitle)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(DashboardTheme.Colors.textTertiary)

            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)
            }

            if let secondaryButtonTitle, let secondaryAction {
                Button(secondaryButtonTitle, action: secondaryAction)
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.entrance), value: appeared)
        .onAppear { appeared = true }
    }
}
