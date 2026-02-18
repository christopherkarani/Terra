import SwiftUI

/// A semi-transparent overlay that shows a spinner and status message.
struct LoadingOverlayView: View {
    let message: String
    let isVisible: Bool

    var body: some View {
        ZStack {
            if isVisible {
                Color(.windowBackgroundColor)
                    .opacity(0.7)

                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)

                    Text(message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DashboardTheme.Colors.textSecondary)
                }
            }
        }
        .animation(DashboardTheme.Animation.standard, value: isVisible)
    }
}
