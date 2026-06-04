import SwiftUI

struct ChatInfoSheet: View {
    let chat: Chat
    @Environment(\.dismiss) private var dismiss
    @State private var selectedParticipant: ChatParticipant?

    private static let participantPreviewLimit = 15

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    row("Type", value: chat.isGroupChat ? "Group" : "Direct Message")

//                    if let lastActivity = chat.lastActivityText {
//                        row("Last Activity", value: lastActivity)
//                    }

                    if let accountID = chat.accountID {
                        row("Account", value: accountID)
                    }
                }

//                Section("Status") {
//                    row("Unread", value: "\(chat.unreadCount)")
//
//                    if let muted = chat.isMuted {
//                        row("Muted", value: muted ? "Yes" : "No")
//                    }
//
//                    if let pinned = chat.isPinned {
//                        row("Pinned", value: pinned ? "Yes" : "No")
//                    }
//
//                    if let archived = chat.isArchived {
//                        row("Archived", value: archived ? "Yes" : "No")
//                    }
//                }

                if let participants = chat.participants {
                    let totalCount = participants.total ?? participants.items.count
                    let visibleParticipants = Array(participants.items.prefix(Self.participantPreviewLimit))
                    let remaining = max(0, totalCount - visibleParticipants.count)

                    Section("Participants (\(totalCount))") {
                        ForEach(visibleParticipants) { participant in
                            Button {
                                selectedParticipant = participant
                            } label: {
                                HStack(spacing: 10) {
                                    ProfileAvatarView(
                                        name: participant.displayName,
                                        imageURLString: participant.imgURL,
                                        dimension: 32
                                    )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(participant.displayName)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.primary)

                                        // if let username = participant.username, username != participant.displayName {
                                            // Text(username)
                                                // .font(.caption)
                                                // .foregroundStyle(.secondary)
                                        // }
                                    }

                                    Spacer()

                                    if participant.isSelf == true {
                                        Text("You")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }

                        if remaining > 0 {
                            Text("^[\(remaining) more member](inflect: true)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Identifiers") {
                    row("Chat ID", value: chat.id, monospaced: true)
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
    }

    private func row(_ label: String, value: String, monospaced: Bool = false) -> some View {
        LabeledContent(label) {
            Text(value)
                .foregroundStyle(.secondary)
                .font(monospaced ? .caption.monospaced() : nil)
                .textSelection(.enabled)
        }
    }
}
