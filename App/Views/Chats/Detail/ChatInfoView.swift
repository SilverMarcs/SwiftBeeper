import SwiftUI

/// The one details screen for a chat. A DM leads with the other person; a group
/// leads with the group and lists its members.
struct ChatInfoView: View {
    let chat: Chat
    let onOpenChat: (Chat) -> Void
    @Environment(ChatStore.self) private var chatStore
    @Environment(\.dismiss) private var dismiss
    /// A fetch with more participants, when the passed chat holds only a preview.
    @State private var detailedParticipants: ChatParticipants?

    private static let participantPreviewLimit = 15

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 16) {
                        ChatInfoHeader(
                            title: chat.displayTitle,
                            subtitle: ChatInfoSubtitle.chat(chat, network: chatStore.networkName(forAccountID: chat.accountID))
                        ) {
                            ChatAvatarView(chat: chat, dimension: 96, allowsFullscreen: true)
                        }

                        ChatInfoActions(chat: chat)
                    }
                    // Keeps the tiles clear of the section's rounded clip.
                    .padding(.bottom, 8)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init())
                }

                if chat.isGroupChat, let participants = detailedParticipants ?? chat.participants {
                    ChatInfoMembersSection(participants: participants, previewLimit: Self.participantPreviewLimit)
                }
            }
            .formStyle(.grouped)
            // The header already names the chat, so the bar shows only its buttons.
            .infoScreenChrome(title: "Chat Info")
            .navigationDestination(for: ChatInfoDestination.self) { destination in
                switch destination {
                case .participant(let participant):
                    ParticipantInfoView(participant: participant, sourceChat: chat, onOpenChat: openChat)
                }
            }
            .toolbar {
                InfoSheetCloseButton { dismiss() }
            }
        }
        .frame(minWidth: 400, minHeight: 450)
        .task(id: chat.id) {
            guard chat.isGroupChat, chat.participants?.hasMore == true else { return }
            let detail = try? await APIClient.getChat(chatID: chat.id, maxParticipantCount: Self.participantPreviewLimit)
            detailedParticipants = detail?.participants
        }
    }

    private func openChat(_ chat: Chat) {
        onOpenChat(chat)
        dismiss()
    }
}
