import SwiftUI

/// A chat member's avatar, name, network, username, and identifier.
struct ParticipantProfileSheet: View {
    let participant: ChatParticipant
    let sourceChat: Chat
    var onOpenChat: ((Chat) -> Void)? = nil
    @Environment(ChatStore.self) private var chatStore
    @Environment(\.dismiss) private var dismiss
    @State private var isOpeningChat = false
    @State private var messageError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        ProfileAvatarView(participant: participant, dimension: 96, allowsFullscreen: true)

                        VStack(spacing: 2) {
                            Text(participant.displayName)
                                .font(.title3)
                                .fontWeight(.semibold)

                            if let username = participant.username,
                               !username.isEmpty,
                               username != participant.displayName {
                                Text(username)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section("Profile") {
                    InfoRow("Name", value: participant.displayName)
                    InfoRow("Network", value: chatStore.connectedAccounts.first {
                        $0.accountID == sourceChat.accountID
                    }?.network ?? "Unknown")

                    if let username = participant.username, !username.isEmpty {
                        InfoRow("Username", value: username)
                    }

                    if participant.isSelf == true {
                        InfoRow("Account", value: "You")
                    }
                }

                Section("Identifiers") {
                    InfoRow("Participant ID", value: participant.id, monospaced: true)
                }
            }
            .navigationTitle("Profile")
            .toolbarTitleDisplayMode(.inline)
            .formStyle(.grouped)
            .toolbar {
                ToolbarItem(placement: messageButtonPlacement) {
                    if sourceChat.isGroupChat, participant.isSelf != true,
                       participant.id != chatStore.currentUserProfile?.id, onOpenChat != nil {
                        Button("Message \(participant.displayName)", systemImage: "bubble.left") {
                            isOpeningChat = true
                        }
                        .labelStyle(.iconOnly)
                        .disabled(isOpeningChat)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 420)
        .task(id: isOpeningChat) {
            if isOpeningChat { await openDirectChat() }
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

    private var messageButtonPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .automatic
        #endif
    }

    private func openDirectChat() async {
        let session = chatStore.session
        defer { isOpeningChat = false }
        do {
            let chat = try await APIClient.findDirectChat(participantID: participant.id, sourceChatID: sourceChat.id)
            guard !Task.isCancelled, chatStore.session == session else { return }
            guard let chat else {
                messageError = "No existing direct chat with this participant was found on this network."
                return
            }
            onOpenChat?(chat)
            dismiss()
        } catch {
            guard !Task.isCancelled, chatStore.session == session,
                  !chatStore.isCancellationLikeError(error) else { return }
            messageError = error.localizedDescription
        }
    }
}
