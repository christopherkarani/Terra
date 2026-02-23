import SwiftUI

/// Draggable divider handle between the center content area and bottom panel.
struct ResizableDividerHandle: View {
    @Binding var height: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat

    @State private var isDragging = false
    @State private var isHovered = false

    private let defaultHeight: CGFloat = 250

    var body: some View {
        Rectangle()
            .fill(isDragging ? DashboardTheme.Colors.borderStrong : DashboardTheme.Colors.borderDefault)
            .frame(height: 1)
            .overlay {
                Capsule()
                    .fill(isDragging ? DashboardTheme.Colors.accentActive : (isHovered ? DashboardTheme.Colors.borderStrong : DashboardTheme.Colors.textQuaternary))
                    .frame(width: 36, height: 4)
                    .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.micro), value: isDragging)
                    .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.micro), value: isHovered)
            }
            .frame(height: 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        let new = height - value.translation.height
                        height = min(max(new, minHeight), maxHeight)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .onTapGesture(count: 2) {
                DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.smooth) {
                    height = min(max(defaultHeight, minHeight), maxHeight)
                }
            }
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .accessibilityLabel("Panel resize handle")
            .accessibilityHint("Drag to resize bottom panel, double-click to reset")
    }
}
