import SwiftUI

/// Picks one inbox or service to filter the chat list by.
struct ChatFilterMenu: View {
    @Environment(ChatStore.self) private var chatStore

    var body: some View {
        Menu {
            Section("Inboxes") {
                ForEach(InboxFilter.allCases, id: \.self) { filter in
                    Toggle(isOn: selection(of: .inbox(filter))) {
                        Label(filter.label, systemImage: filter.systemImage)
                    }
                }
            }

            Divider()

            Section("Services") {
                ForEach(chatStore.availableServiceFilters, id: \.self) { filter in
                    Toggle(filter.label, isOn: selection(of: filter))
                }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease")
        }
        .menuOrder(.fixed)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// On when `filter` is selected; turning it on selects it. Turning the
    /// selected filter off does nothing, so one filter is always active.
    private func selection(of filter: ChatFilter) -> Binding<Bool> {
        Binding(
            get: { chatStore.selectedFilter == filter },
            set: { if $0 { chatStore.selectedFilter = filter } }
        )
    }
}
