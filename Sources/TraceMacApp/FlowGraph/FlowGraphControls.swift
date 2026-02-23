import SwiftUI

/// Bottom-right overlay with zoom in/out buttons and percentage text.
/// White background, 1px border, 8px radius, slight shadow.
struct FlowGraphControls: View {
    @Binding var zoomScale: CGFloat
    let minZoom: CGFloat
    let maxZoom: CGFloat
    let isExpanded: Bool
    var onFitToView: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            if let onFitToView {
                Button {
                    onFitToView()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DashboardTheme.Colors.textSecondary)
                .accessibilityLabel("Fit to view")
                .help("Fit graph to viewport")

                Divider()
                    .frame(height: 16)
            }

            Button {
                DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                    zoomScale = max(zoomScale - 0.25, minZoom)
                }
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DashboardTheme.Colors.textSecondary)
            .accessibilityLabel("Zoom out")
            .help("Zoom out")

            Text("\(Int(zoomScale * 100))%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DashboardTheme.Colors.textTertiary)
                .frame(width: 36)

            Button {
                DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                    zoomScale = min(zoomScale + 0.25, maxZoom)
                }
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DashboardTheme.Colors.textSecondary)
            .accessibilityLabel("Zoom in")
            .help("Zoom in")

            Divider()
                .frame(height: 16)

            Image(systemName: isExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                .font(.system(size: 11))
                .foregroundStyle(DashboardTheme.Colors.textTertiary)
                .accessibilityLabel(isExpanded ? "Compact view" : "Expanded view")
                .help(isExpanded ? "Switch to compact node view" : "Switch to expanded node view")
        }
        .padding(.horizontal, DashboardTheme.Spacing.lg)
        .padding(.vertical, DashboardTheme.Spacing.md)
        .background(DashboardTheme.Colors.windowBackground)
        .clipShape(.rect(cornerRadius: DashboardTheme.Spacing.cornerRadiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTheme.Spacing.cornerRadiusLarge)
                .strokeBorder(DashboardTheme.Colors.borderDefault, lineWidth: 1)
        )
        .shadow(color: DashboardTheme.Shadows.md.color, radius: DashboardTheme.Shadows.md.radius, y: DashboardTheme.Shadows.md.y)
    }
}
