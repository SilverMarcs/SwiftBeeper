import SwiftUI

/// A chat member's avatar, name, username, and identifier.
struct ParticipantProfileSheet: View {
    let participant: ChatParticipant
    @Environment(\.dismiss) private var dismiss

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
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 420)
    }
}
