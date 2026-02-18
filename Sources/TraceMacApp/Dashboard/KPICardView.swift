import SwiftUI

struct KPICardView: View {
    let symbolName: String
    let label: String
    let value: String
    var accent: Color = DashboardTheme.accentNormal

    @State private var isHovered = false

    var body: some View {
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
        .dashboardCard()
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(DashboardTheme.quick, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
