import SwiftUI

/// The groups you share with a person; picking one opens it.
struct ChatInfoCommonGroupsSection: View {
    /// Light copies holding only what the rows show.
    let groups: [Chat]
    let onOpenChat: (Chat) -> Void

    @Environment(ChatStore.self) private var chatStore
    @State private var openingChatID: Chat.ID?

    var body: some View {
        if !groups.isEmpty {
            Section("Groups in Common") {
                ForEach(groups) { group in
                    Button {
                        Task { await open(group) }
                    } label: {
                        ChatCommonGroupRow(chat: group)
                    }
                    .buttonStyle(.plain)
                    .disabled(openingChatID != nil)
                }
            }
        }
    }

    /// Opens the full chat, with its preview, read state and settings, which
    /// the light copy leaves out.
    private func open(_ group: Chat) async {
        openingChatID = group.id
        defer { openingChatID = nil }
        if let listed = chatStore.chat(byID: group.id) {
            onOpenChat(listed)
        } else {
            let fetched = try? await APIClient.getChat(chatID: group.id)
            onOpenChat(fetched ?? group)
        }
    }
}
