import SwiftUI

struct ParticipantProfileSheet: View {
    let participant: ChatParticipant
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        ProfileAvatarView(
                            name: participant.displayName,
                            imageURLString: participant.imgURL,
                            dimension: 96
                        )

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
                    row("Name", value: participant.displayName)

                    if let username = participant.username, !username.isEmpty {
                        row("Username", value: username)
                    }

                    if participant.isSelf == true {
                        row("Account", value: "You")
                    }

                    if participant.cannotMessage == true {
                        row("Messaging", value: "Unavailable")
                    }
                }

                Section("Identifiers") {
                    row("Participant ID", value: participant.id, monospaced: true)
                }
            }
            .formStyle(.grouped)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .cancel) { dismiss() }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 420)
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
