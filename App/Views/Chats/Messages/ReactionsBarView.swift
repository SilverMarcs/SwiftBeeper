import SwiftUI

/// A message's reactions; tapping one toggles the current user's reaction.
struct ReactionsBarView: View {
    @Environment(ChatStore.self) private var chatStore

    let message: Message
    let chat: Chat

    var body: some View {
        if let groupedReactions = message.groupedReactions {
            let selfID = chat.participants?.items.first { $0.isSelf == true }?.id
            HStack(spacing: 4) {
                ForEach(groupedReactions) { group in
                    let isOwn = selfID.map { group.participantIDs.contains($0) } ?? false

                    Button {
                        toggle(group.reactionKey, isOwn: isOwn)
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
            .offset(x: message.isSender ? -15 : 15, y: 1)
        }
    }

    private func toggle(_ reactionKey: String, isOwn: Bool) {
        Task {
            if isOwn {
                await chatStore.removeReaction(from: message.id, in: message.chatID, reactionKey: reactionKey)
            } else {
                await chatStore.addReaction(to: message.id, in: message.chatID, reactionKey: reactionKey)
            }
        }
    }
}
