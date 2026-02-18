import SwiftUI

/// A small pill badge indicating success ("OK") or error ("Error").
struct StatusBadge: View {
    let isError: Bool

    var body: some View {
        Text(isError ? "Error" : "OK")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(isError ? DashboardTheme.Colors.accentError : DashboardTheme.Colors.accentSuccess)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                (isError ? DashboardTheme.Colors.accentError : DashboardTheme.Colors.accentSuccess)
                    .opacity(0.12)
            )
            .clipShape(.capsule)
    }
}
