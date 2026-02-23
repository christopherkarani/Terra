import SwiftUI

/// Semantic status kinds for badges.
enum StatusKind {
    case ok
    case error
    case warning
    case pending

    var label: String {
        switch self {
        case .ok: "OK"
        case .error: "Error"
        case .warning: "Warning"
        case .pending: "Pending"
        }
    }

    var color: Color {
        switch self {
        case .ok: DashboardTheme.Colors.accentSuccess
        case .error: DashboardTheme.Colors.accentError
        case .warning: DashboardTheme.Colors.accentWarning
        case .pending: DashboardTheme.Colors.textTertiary
        }
    }
}

/// 6px dot + text badge with semantic background.
struct StatusBadge: View {
    let kind: StatusKind

    /// Legacy convenience initializer.
    init(isError: Bool) {
        self.kind = isError ? .error : .ok
    }

    init(kind: StatusKind) {
        self.kind = kind
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(kind.color)
                .frame(width: 6, height: 6)

            Text(kind.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(kind.color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(kind.color.opacity(0.06))
        .clipShape(.rect(cornerRadius: DashboardTheme.Spacing.cornerRadiusSmall))
    }
}
