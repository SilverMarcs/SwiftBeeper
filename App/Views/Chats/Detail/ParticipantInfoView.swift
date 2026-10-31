import SwiftUI

/// A person's info, laid out like a DM's chat info and acting on your DM with
/// them on the source chat's network. Reached from a group, it also offers Message.
struct ParticipantInfoView: View {
    let participant: ChatParticipant
    let sourceChat: Chat
    let onOpenChat: (Chat) -> Void
    @Environment(ChatStore.self) private var chatStore
    /// The existing DM with this person, once the local lookup finds it.
    @State private var directChat: Chat?
    @State private var lookupError: String?
    @State private var messageError: String?

    var body: some View {
        let isSelf = participant.isSelf == true || participant.id == chatStore.currentUserProfile?.id
        let network = chatStore.networkName(forAccountID: sourceChat.accountID)

        Form {
            Section {
                VStack(spacing: 16) {
                    ChatInfoHeader(
                        title: participant.displayName,
                        subtitle: ChatInfoSubtitle.participant(participant, network: network)
                    ) {
                        ProfileAvatarView(participant: participant, dimension: 96, allowsFullscreen: true)
                    }

                    if !isSelf {
                        ChatInfoActions(
                            chat: directChat,
                            onMessage: sourceChat.isGroupChat ? openDirectChat : nil,
                            onChatUpdated: refreshDirectChat
                        )
                    }
                }
                // Keeps the tiles clear of the section's rounded clip.
                .padding(.bottom, 8)
                .listRowBackground(Color.clear)
                .listRowInsets(.init())
            }
        }
        .formStyle(.grouped)
        .infoScreenChrome(title: "Contact Info")
        .task(id: participant.id) {
            guard !isSelf else { return }
            await lookUpDirectChat()
        }
        .alert("Could Not Open Chat", isPresented: Binding(
            get: { messageError != nil },
            set: { if !$0 { messageError = nil } }
        )) {
            Button("OK", role: .cancel) { messageError = nil }
        } message: {
            Text(messageError ?? "")
        }
    }

    private func openDirectChat() {
        if let directChat {
            onOpenChat(directChat)
        } else {
            messageError = lookupError ?? "No existing direct chat with this participant was found on this network."
        }
    }

    private func lookUpDirectChat() async {
        let session = chatStore.session
        do {
            let chat = try await APIClient.findDirectChat(participantID: participant.id, sourceChatID: sourceChat.id)
            guard !Task.isCancelled, chatStore.session == session else { return }
            directChat = chat
        } catch {
            guard !Task.isCancelled, chatStore.session == session,
                  !chatStore.isCancellationLikeError(error) else { return }
            lookupError = error.localizedDescription
        }
    }

    /// Re-reads the DM so the buttons reflect an action, even when the DM
    /// isn't in the loaded sidebar.
    private func refreshDirectChat() async {
        guard let chatID = directChat?.id,
              let chat = try? await APIClient.getChat(chatID: chatID) else { return }
        directChat = chat
    }
}
