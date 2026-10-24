import SwiftUI

/// The chat's type, account, members, and identifiers.
struct ChatInfoSheet: View {
    let chat: Chat
    @Environment(\.dismiss) private var dismiss
    @State private var selectedParticipant: ChatParticipant?
    /// A fetch with more participants, when the passed chat holds only a preview.
    @State private var detail: Chat?

    private static let participantPreviewLimit = 15

    var body: some View {
        let chat = detail ?? self.chat
        NavigationStack {
            Form {
                Section("General") {
                    InfoRow("Type", value: chat.isGroupChat ? "Group" : "Direct Message")

                    if let accountID = chat.accountID {
                        InfoRow("Account", value: accountID)
                    }
                }

                if let participants = chat.participants {
                    let totalCount = participants.total ?? participants.items.count
                    let visibleParticipants = participants.items.prefix(Self.participantPreviewLimit)
                    let remaining = max(0, totalCount - visibleParticipants.count)

                    Section("Participants (\(totalCount))") {
                        ForEach(visibleParticipants) { participant in
                            ParticipantRow(participant: participant) {
                                selectedParticipant = participant
                            }
                        }

                        if remaining > 0 {
                            Text("^[\(remaining) more member](inflect: true)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Identifiers") {
                    InfoRow("Chat ID", value: chat.id, monospaced: true)
                }
            }
            .navigationTitle("Chat Info")
            .toolbarTitleDisplayMode(.inline)
            .formStyle(.grouped)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 350)
        .sheet(item: $selectedParticipant) { participant in
            ParticipantProfileSheet(participant: participant)
        }
        .task(id: chat.id) {
            guard chat.participants?.hasMore == true else { return }
            detail = try? await APIClient.getChat(chatID: chat.id, maxParticipantCount: Self.participantPreviewLimit)
        }
    }
}
