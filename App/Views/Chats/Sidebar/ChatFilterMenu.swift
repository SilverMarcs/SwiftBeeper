import SwiftUI

/// Picks one inbox or network login to filter the chat list by.
struct ChatFilterMenu: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(\.displayScale) private var displayScale
    @State private var networkIcons = NetworkIconStore()

    var body: some View {
        let networkFilters = chatStore.networkFilters
        Menu {
            Section("Inboxes") {
                ForEach(InboxFilter.allCases, id: \.self) { filter in
                    Toggle(isOn: selection(of: .inbox(filter))) {
                        Label(filter.label, systemImage: filter.systemImage)
                    }
                }
            }

            Divider()

            Section("Networks") {
                ForEach(networkFilters, id: \.self) { filter in
                    Toggle(isOn: selection(of: .network(filter))) {
                        NetworkFilterLabel(filter: filter, icon: filter.imageURL.flatMap { networkIcons.icons[$0] })
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(chatStore.selectedFilter != .inbox(.primary) ? Color(.accent) : .primary)
        }
        .accessibilityLabel("Filter")
        .menuOrder(.fixed)
        .menuIndicator(.hidden)
        .fixedSize()
        // Loaded with the button, so the icons are ready when the menu opens.
        .task(id: networkFilters.compactMap(\.imageURL)) {
            await networkIcons.load(networkFilters, pointSize: Self.iconPointSize, displayScale: displayScale)
        }
    }

    /// Menus show a bitmap at its own size: a row symbol's size on each platform.
    #if os(macOS)
    private static let iconPointSize: CGFloat = 16
    #else
    private static let iconPointSize: CGFloat = 22
    #endif

    /// On when `filter` is selected; turning it on selects it. Turning the
    /// selected filter off does nothing, so one filter is always active.
    private func selection(of filter: ChatFilter) -> Binding<Bool> {
        Binding(
            get: { chatStore.selectedFilter.id == filter.id },
            set: { if $0 { chatStore.selectedFilter = filter } }
        )
    }
}
