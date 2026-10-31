import SwiftUI

/// A group's members; each row pushes that member's profile.
struct ChatInfoMembersSection: View {
    let participants: ChatParticipants
    let previewLimit: Int

    var body: some View {
        let totalCount = participants.total ?? participants.items.count
        let visibleParticipants = participants.items.prefix(previewLimit)
        let remaining = max(0, totalCount - visibleParticipants.count)

        Section("Members (\(totalCount))") {
            ForEach(visibleParticipants) { participant in
                NavigationLink(value: ChatInfoDestination.participant(participant)) {
                    ParticipantRow(participant: participant)
                }
            }

            if remaining > 0 {
                Text("^[\(remaining) more member](inflect: true)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
