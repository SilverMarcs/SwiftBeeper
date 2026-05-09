import SwiftUI

struct GroupedReaction: Identifiable {
    var id: String { reactionKey }
    let reactionKey: String
    var count: Int
    var participantIDs: [String]
}

struct ReactionsBarView: View {
    let groupedReactions: [GroupedReaction]
    let currentParticipantID: String?
    let onToggle: (String, Bool) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(groupedReactions) { group in
                let isOwn = currentParticipantID.map { id in group.participantIDs.contains(id) } ?? false

                Button {
                    onToggle(group.reactionKey, isOwn)
                } label: {
                    HStack(spacing: 2) {
                        Text(group.reactionKey)
                            .font(.caption)
                        if group.count > 1 {
                            Text("\(group.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ChatVisualStyle.reactionFill(isSelected: isOwn))
                    .clipShape(.capsule)
                    .overlay(
                        Capsule()
                            .strokeBorder(isOwn ? Color.accentColor : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
