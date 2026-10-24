import SwiftUI

/// The selectable chat rows, loading more as the end scrolls into view.
struct ChatListView: View {
    @Environment(ChatStore.self) private var chatStore

    var body: some View {
        // Compute once for the rows and animation key.
        let displayedChats = chatStore.displayedChats
        List(selection: Bindable(chatStore).selectedChatID) {
            ForEach(displayedChats) { chat in
                ChatRowView(chat: chat)
                    .listRowSeparator(.hidden, edges: .top)
                    .listRowSeparator(.visible, edges: .bottom)
                    .if(isMacOrPad) {
                        $0.listRowSeparatorTint(.primary.opacity(0.1), edges: .bottom)
                    }
                    .tag(chat.id)
            }

            if chatStore.hasMoreChats, chatStore.searchQuery.isBlank {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    .task {
                        await chatStore.loadMoreChats()
                    }
            }
        }
        .if(isIPhone) { $0.listStyle(.plain) }
        // Animate only when the row order/membership changes (keyed on the id
        // sequence), not on in-place row edits like a chat's last-message text.
        .animation(.default, value: displayedChats.map(\.id))
        .overlay {
            ChatListOverlay(isEmpty: displayedChats.isEmpty)
        }
    }
}
