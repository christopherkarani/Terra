import SwiftUI

struct KPICardView: View {
    let symbolName: String
    let label: String
    let value: String
    var accent: Color = DashboardTheme.accentNormal

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1)
                .fill(accent)
                .frame(height: 2)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: symbolName)
                        .foregroundStyle(accent)

                    Text(label)
                        .font(DashboardTheme.kpiLabel)
                        .foregroundStyle(.secondary)
                }

                Text(value)
                    .font(DashboardTheme.kpiValue)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DashboardTheme.contentPadding)
        }
        .background(
            RoundedRectangle(cornerRadius: DashboardTheme.cornerRadius)
                .fill(accent.opacity(isHighlighted ? 0.06 : 0))
        )
        .dashboardCard()
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(DashboardTheme.quick, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var isHighlighted: Bool {
        accent == DashboardTheme.accentError || accent == DashboardTheme.accentWarning
    }
}
