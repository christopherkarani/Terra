import SwiftUI
import TerraTraceKit

/// Two-column key-value table using LazyVStack.
/// 140px key column (11pt mono secondary), value column (11pt mono primary),
/// alternating row backgrounds, copy context menu.
private enum SortColumn { case key, value }
private enum SortDirection { case ascending, descending }

struct SpanAttributesTable: View {
    let items: [AttributeItem]
    @State private var searchQuery = ""
    @State private var sortColumn: SortColumn = .key
    @State private var sortDirection: SortDirection = .ascending

    private var filteredItems: [AttributeItem] {
        let base: [AttributeItem]
        if searchQuery.isEmpty {
            base = items
        } else {
            let query = searchQuery.lowercased()
            base = items.filter {
                $0.key.lowercased().contains(query) || $0.value.lowercased().contains(query)
            }
        }
        return base.sorted { a, b in
            let result: Bool
            switch sortColumn {
            case .key: result = a.key.localizedCaseInsensitiveCompare(b.key) == .orderedAscending
            case .value: result = a.value.count < b.value.count
            }
            return sortDirection == .ascending ? result : !result
        }
    }

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView(
                "No Attributes",
                systemImage: "list.bullet",
                description: Text("This span has no attributes")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Search + copy-all row
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundStyle(DashboardTheme.Colors.textTertiary)

                        TextField("Filter attributes…", text: $searchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 10, design: .monospaced))

                        if !searchQuery.isEmpty {
                            Text("\(filteredItems.count) of \(items.count)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(DashboardTheme.Colors.textTertiary)
                        }

                        Spacer()

                        Button {
                            let text = items.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
                            copyToPasteboard(text)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundStyle(DashboardTheme.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy all attributes")
                    }
                    .padding(.horizontal, DashboardTheme.Spacing.md)
                    .padding(.vertical, DashboardTheme.Spacing.sm)

                    Divider()

                    // Header with sortable columns
                    HStack(spacing: 0) {
                        sortableHeader("KEY", column: .key)
                            .frame(width: 140, alignment: .leading)

                        sortableHeader("VALUE", column: .value)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, DashboardTheme.Spacing.md)
                    .padding(.vertical, DashboardTheme.Spacing.sm)

                    Divider()

                    ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                        AttributeRowView(item: item, isAlternate: index % 2 != 0)
                    }
                }
            }
        }
    }

    private func sortableHeader(_ title: String, column: SortColumn) -> some View {
        Button {
            if sortColumn == column {
                sortDirection = sortDirection == .ascending ? .descending : .ascending
            } else {
                sortColumn = column
                sortDirection = .ascending
            }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DashboardTheme.Colors.textTertiary)
                if sortColumn == column {
                    Image(systemName: sortDirection == .ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(DashboardTheme.Colors.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Single attribute row with hover highlight, help tooltips on truncation, and context menu.
private struct AttributeRowView: View {
    let item: AttributeItem
    let isAlternate: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Text(item.key)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DashboardTheme.Colors.textSecondary)
                .frame(width: 140, alignment: .leading)
                .lineLimit(1)
                .help(item.key)

            Text(item.value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DashboardTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .help(item.value)
        }
        .padding(.horizontal, DashboardTheme.Spacing.md)
        .padding(.vertical, DashboardTheme.Spacing.sm + 1)
        .background(isHovered ? DashboardTheme.Colors.surfaceHover : (isAlternate ? DashboardTheme.Colors.surfaceRaised : Color.clear))
        .animation(DashboardTheme.Animation.accessible(DashboardTheme.Animation.micro), value: isHovered)
        .contentShape(.rect)
        .onHover { hovering in isHovered = hovering }
        .contextMenu {
            Button("Copy Key") {
                copyToPasteboard(item.key)
            }
            Button("Copy Value") {
                copyToPasteboard(item.value)
            }
            Divider()
            Button("Copy Key=Value") {
                copyToPasteboard("\(item.key)=\(item.value)")
            }
        }
    }
}

private func copyToPasteboard(_ string: String) {
    #if canImport(AppKit)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
    #endif
}
