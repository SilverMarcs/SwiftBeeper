import SwiftUI

/// The selectable chat rows, loading more as the end scrolls into view.
struct ChatListView: View {
    @Environment(ChatStore.self) private var chatStore
    /// How many rows before the end the next page starts loading.
    private static let prefetchDistance = 10

    var body: some View {
        // Compute once for the rows and animation key.
        let displayedChats = chatStore.displayedChats
        // The next page loads while this row scrolls in, well before the end.
        let prefetchChatID = displayedChats.dropLast(Self.prefetchDistance).last?.id
        List(selection: Bindable(chatStore).selectedChatID) {
            ForEach(displayedChats) { chat in
                ChatRowView(chat: chat)
                    .listRowSeparator(.hidden, edges: .top)
                    .listRowSeparator(.visible, edges: .bottom)
                    .if(isMacOrPad) {
                        $0.listRowSeparatorTint(.primary.opacity(0.1), edges: .bottom)
                    }
                    .tag(chat.id)
                    .onAppear {
                        guard chat.id == prefetchChatID, chatStore.hasMoreChats, !chatStore.isSearchActive else { return }
                        Task { await chatStore.loadMoreChats() }
                    }
            }

            if chatStore.hasMoreChats, !chatStore.isSearchActive {
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
        // sequence), not on in-place row edits like a chat's last-message text,
        // and not when a page appends below: animating those rows in while
        // the list scrolls made it jump.
        .animation(.default, value: ChatListOrder(ids: displayedChats.map(\.id)))
        .overlay {
            ChatListOverlay(isEmpty: displayedChats.isEmpty)
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
}
