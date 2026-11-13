import SwiftUI

/// Leaving a group and deleting the chat, each confirmed first.
struct ChatInfoRemovalSection: View {
    let chat: Chat
    /// Whether the chat's network deletes the chat itself, rather than Relay
    /// only leaving it.
    let canDeleteChat: Bool
    let onRemoved: () -> Void

    @Environment(ChatStore.self) private var chatStore
    @State private var pendingRemoval: ChatRemoval?
    @State private var isRemoving = false
    @State private var errorMessage: String?

    var body: some View {
        let network = chatStore.networkName(forAccountID: chat.accountID)
        Section {
            if chat.isGroupChat {
                Button("Leave Group", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    pendingRemoval = .leave
                }
            }

            // A group only deletes where its network can; leaving covers the rest.
            if !chat.isGroupChat || canDeleteChat {
                Button("Delete Chat", systemImage: "trash", role: .destructive) {
                    pendingRemoval = .delete
                }
            }
        }
        // A form row tints its label's icon with the list item tint (the app
        // accent) even for a destructive role, which only reddens the title.
        .listItemTint(.red)
        .disabled(isRemoving)
        .confirmationDialog(
            pendingRemoval?.confirmationTitle ?? "",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { removal in
            Button(removal.actionTitle, role: .destructive) {
                Task { await remove(removal) }
            }
        } message: { removal in
            Text(removal.confirmationMessage(network: network, canDeleteChat: canDeleteChat))
        }
        .alert("Couldn't Remove Chat", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func remove(_ removal: ChatRemoval) async {
        isRemoving = true
        defer { isRemoving = false }
        do {
            switch removal {
            case .leave: try await chatStore.leaveChat(chat.id)
            case .delete: try await chatStore.deleteChat(chat.id)
            }
            onRemoved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
