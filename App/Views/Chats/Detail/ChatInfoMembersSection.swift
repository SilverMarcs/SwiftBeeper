import SwiftUI

/// A group's members; each row pushes that member's profile.
struct ChatInfoMembersSection: View {
    @Environment(ChatStore.self) private var chatStore

    let chat: Chat
    let participants: ChatParticipants
    let previewLimit: Int

    var body: some View {
        let totalCount = participants.total ?? participants.items.count
        let visibleParticipants = participants.items.prefix(previewLimit)
        let remaining = max(0, totalCount - visibleParticipants.count)

        Section("Members (\(totalCount))") {
            ForEach(visibleParticipants) { participant in
                NavigationLink(value: ChatInfoDestination.participant(participant)) {
                    ParticipantRow(participant: chatStore.displayedParticipant(participant, in: chat))
                }
            }

            if remaining > 0 {
                Text("^[\(remaining) more member](inflect: true)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
