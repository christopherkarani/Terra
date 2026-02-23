import SwiftUI

struct EventCategoryFilterBar: View {
    @Bindable var viewModel: TraceEventListViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterPill(label: "ALL", count: viewModel.allEvents.count, color: DashboardTheme.Colors.textSecondary, isSelected: viewModel.selectedCategory == nil) {
                    viewModel.selectedCategory = nil
                }

                ForEach(EventCategory.allCases, id: \.self) { category in
                    let count = viewModel.categoryCounts[category] ?? 0
                    if count > 0 {
                        filterPill(
                            label: category.displayName.uppercased(),
                            count: count,
                            color: category.color,
                            isSelected: viewModel.selectedCategory == category
                        ) {
                            if viewModel.selectedCategory == category {
                                viewModel.selectedCategory = nil
                            } else {
                                viewModel.selectedCategory = category
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func filterPill(label: String, count: Int, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)

                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.3)

                Text("\(count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DashboardTheme.Colors.textTertiary)
            }
            .foregroundStyle(isSelected ? DashboardTheme.Colors.textPrimary : DashboardTheme.Colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? color.opacity(0.15) : DashboardTheme.Colors.surfaceRaised)
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}
