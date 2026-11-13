import SwiftUI

/// The selectable chat rows, loading more as the end scrolls into view.
/// Searching shows matching chats, then matching messages.
struct ChatListView: View {
    @Environment(ChatStore.self) private var chatStore
    @AppStorage(ChatNetworkIcons.storageKey) private var showsNetworkIcons = true
    /// How many rows before the end the next page starts loading.
    private static let prefetchDistance = 10

    var body: some View {
        // Compute once for the rows and animation key.
        let displayedChats = chatStore.displayedChats
        // The next page loads while this row scrolls in, well before the end.
        let prefetchChatID = displayedChats.dropLast(Self.prefetchDistance).last?.id
        let isSearching = chatStore.isSearchActive
        let networkImageURLs = showsNetworkIcons ? chatStore.networkImageURLsByAccountID : [:]
        // Only iPad draws separators against the selection highlight, so only
        // iPad reads the selection here.
        let separatorlessChatIDs = isIPad ? Self.separatorlessChatIDs(in: displayedChats, selectedChatID: chatStore.selectedChatID) : []
        List(selection: Bindable(chatStore).selectedChatID) {
            if isSearching {
                if !displayedChats.isEmpty {
                    Section("Chats") {
                        ForEach(displayedChats) { chat in
                            ChatListRow(
                                chat: chat,
                                networkImageURL: chat.accountID.flatMap { networkImageURLs[$0] },
                                hidesBottomSeparator: separatorlessChatIDs.contains(chat.id)
                            )
                        }
                    }
                }

                MessageSearchSection()
            } else {
                ForEach(displayedChats) { chat in
                    ChatListRow(
                        chat: chat,
                        networkImageURL: chat.accountID.flatMap { networkImageURLs[$0] },
                        hidesBottomSeparator: separatorlessChatIDs.contains(chat.id)
                    )
                    .onAppear {
                        guard chat.id == prefetchChatID, chatStore.hasMoreChats, !chatStore.isSearchActive else { return }
                        Task { await chatStore.loadMoreChats() }
                    }
                }

                if chatStore.hasMoreChats {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        .task {
                            await chatStore.loadMoreChats()
                        }
                }
            }
        }
        .if(isIPhone) { $0.listStyle(.plain) }
        // Animate only when the row order/membership changes (keyed on the id
        // sequence), not on in-place row edits like a chat's last-message text.
        // Paging appends without animation; see `loadMoreChats()`.
        .animation(.default, value: displayedChats.map(\.id))
        .overlay {
            ChatListOverlay(isEmpty: displayedChats.isEmpty && (!isSearching || chatStore.messageSearchResults?.isEmpty != false))
        }
        .alert("Could Not Update Pin", isPresented: Binding(
            get: { chatStore.pinError != nil },
            set: { if !$0 { chatStore.pinError = nil } }
        )) {
            Button("OK", role: .cancel) { chatStore.pinError = nil }
        } message: {
            Text(chatStore.pinError ?? "")
        }
    }

    /// The rows whose bottom separator would border the selected row: the
    /// selected row itself and the row above it.
    private static func separatorlessChatIDs(in chats: [Chat], selectedChatID: String?) -> Set<String> {
        guard let selectedChatID, let index = chats.firstIndex(where: { $0.id == selectedChatID }) else { return [] }
        var ids: Set<String> = [selectedChatID]
        if index > chats.startIndex { ids.insert(chats[chats.index(before: index)].id) }
        return ids
    }
}
