import SwiftUI

/// The Messages section of the chat list's search, loading more results as
/// its end scrolls into view. Picking one opens its chat.
struct MessageSearchSection: View {
    @Environment(ChatStore.self) private var chatStore
    @AppStorage(ChatNetworkIcons.storageKey) private var showsNetworkIcons = true

    var body: some View {
        if let results = chatStore.messageSearchResults, !results.isEmpty {
            let query = chatStore.searchQuery.trimmed
            let networkImageURLs = showsNetworkIcons ? chatStore.networkImageURLsByAccountID : [:]
            Section("Messages") {
                ForEach(results) { message in
                    Button {
                        Task { await chatStore.openMessageSearchResult(message) }
                    } label: {
                        let chat = chatStore.messageSearchChats[message.chatID]
                        MessageSearchResultRow(
                            message: message,
                            chat: chat,
                            networkImageURL: chat?.accountID.flatMap { networkImageURLs[$0] },
                            query: query
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden, edges: .top)
                    .listRowSeparator(.visible, edges: .bottom)
                    .if(isMacOrPad) {
                        $0.listRowSeparatorTint(.primary.opacity(0.1), edges: .bottom)
                    }
                }

                if chatStore.hasMoreMessageSearchResults {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        .task(id: results.count) {
                            await chatStore.loadMoreMessageSearchResults()
                        }
                }
            }
        }
    }
}
