import SwiftUI

struct ChatInfoSheet: View {
    let chat: Chat
    @Environment(\.dismiss) private var dismiss

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
                    Section("Participants (\(participants.total ?? participants.items.count))") {
                        ForEach(participants.items) { participant in
                            HStack(spacing: 10) {
                                ProfileAvatarView(
                                    name: participant.displayName,
                                    imageURLString: participant.imgURL,
                                    dimension: 32
                                )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(participant.displayName)
                                        .fontWeight(.medium)

                                    if let username = participant.username, username != participant.displayName {
                                        Text(username)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                if participant.isSelf == true {
                                    Text("You")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Identifiers") {
                    row("Chat ID", value: chat.id, monospaced: true)
                }
            }
//            .navigationTitle(chat.displayTitle)
            .formStyle(.grouped)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 350)
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
