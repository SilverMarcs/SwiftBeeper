import SwiftUI

/// The chat's bookmarked messages, most recently bookmarked first, pushed
/// from chat info. Picking one shows it in the timeline.
struct ChatBookmarksView: View {
    let chat: Chat
    let onOpen: (Message) -> Void
    @Environment(ChatStore.self) private var chatStore
    @State private var messages: [Message] = []
    @State private var hasLoaded = false
    @State private var error: String?

    var body: some View {
        let bookmarks = chatStore.messageBookmarks
        // A removal shows at once, before the core confirms it.
        let shown = messages.filter { bookmarks.contains($0.id, in: chat.id) }
        List {
            ForEach(shown) { message in
                Button {
                    onOpen(message)
                } label: {
                    ChatBookmarkRow(message: message)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    removeButton(for: message)
                }
                .contextMenu {
                    removeButton(for: message)
                }
            }
        }
        .animation(.default, value: shown.map(\.id))
        .navigationTitle("Bookmarks")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
        .overlay {
            if !hasLoaded {
                ProgressView()
            } else if let error, shown.isEmpty {
                ContentUnavailableView("Couldn’t Load Bookmarks", systemImage: "bookmark", description: Text(error))
            } else if shown.isEmpty {
                ContentUnavailableView(
                    "No Bookmarks",
                    systemImage: "bookmark",
                    description: Text("Bookmark a message from its menu to find it here.")
                )
            }
        }
        // Every bookmark change, here or in another Beeper app, reloads it.
        .task(id: bookmarks.messageIDs) {
            await load()
        }
    }

    private func removeButton(for message: Message) -> some View {
        Button("Remove Bookmark", systemImage: "bookmark.slash", role: .destructive) {
            Task { await chatStore.setBookmarked(message, false) }
        }
    }

    private func load() async {
        do {
            let output = try await APIClient.listMessageBookmarks(chatID: chat.id, includeMessages: true)
            guard !Task.isCancelled else { return }
            messages = output.items ?? []
            error = nil
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
        hasLoaded = true
    }
}
