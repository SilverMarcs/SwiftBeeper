import SwiftUI

struct MessageRowView: View {
    @Environment(ChatStore.self) private var chatStore

    let message: Message
    let chat: Chat

    private static let commonReactions = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

    var body: some View {
        HStack(alignment: .bottom) {
            if isOutgoing {
                Spacer(minLength: 100)
            } else if showIncomingIdentity {
                ProfileAvatarView(name: message.senderDisplayName, imageURLString: senderAvatarImageURL, dimension: 28)
            }

            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
                if isOutgoing == false && showIncomingIdentity {
                    Text(message.senderDisplayName)
                        .font(.subheadline)
                        .bold()
                }

                if let linkedMessageID = message.linkedMessageID {
                    ReplyPreviewView(
                        linkedMessageID: linkedMessageID,
                        chatID: message.chatID,
                        isOutgoing: isOutgoing
                    )
                }

                if let attachments = message.attachments, attachments.isEmpty == false {
                    ForEach(attachments) { attachment in
                        AttachmentView(attachment: attachment, isOutgoing: isOutgoing)
                    }
                }

                if message.hasText {
                    Text(message.displayText.markdownAttributed)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isOutgoing ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.background.tertiary))
                        .clipShape(.rect(cornerRadius: 15))
                }

                if let groupedReactions = groupedReactions, groupedReactions.isEmpty == false {
                    ReactionsBarView(
                        groupedReactions: groupedReactions,
                        currentParticipantID: currentParticipant?.id,
                        onToggle: { reactionKey, isOwn in
                            Task {
                                if isOwn {
                                    await chatStore.removeReaction(from: message.id, in: message.chatID, reactionKey: reactionKey)
                                } else {
                                    await chatStore.addReaction(to: message.id, in: message.chatID, reactionKey: reactionKey)
                                }
                            }
                        }
                    )
                }
            }
            .contextMenu {
                ControlGroup {
                    ForEach(Self.commonReactions, id: \.self) { emoji in
                        Button {
                            Task {
                                if hasOwnReaction(for: emoji) {
                                    await chatStore.removeReaction(from: message.id, in: message.chatID, reactionKey: emoji)
                                } else {
                                    await chatStore.addReaction(to: message.id, in: message.chatID, reactionKey: emoji)
                                }
                            }
                        } label: {
                            let label = hasOwnReaction(for: emoji) ? "Remove \(emoji)" : emoji
                            Text(label)
                        }
                    }
                } label: {
                    Label("Reactions", systemImage: "face.smiling.inverse")
                        .labelStyle(.titleAndIcon)
                }
                
                Divider()
                
                Button {
                    chatStore.setReplyTo(message)
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }

                if isOutgoing && canEdit {
                    Button {
                        chatStore.startEditing(message)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                }

            }

            if isOutgoing == false {
                Spacer(minLength: 100)
            }
        }
        .padding(.vertical, 4)
    }

    private var currentParticipant: ChatParticipant? {
        chat.participants?.items.first(where: { $0.isSelf == true })
    }

    private var showIncomingIdentity: Bool {
        !chat.isSingleChat
    }

    private var senderAvatarImageURL: String? {
        chat.participant(with: message.senderID)?.imgURL
    }

    private var canEdit: Bool {
        Date().timeIntervalSince(message.timestamp) <= 15 * 60
    }


    private var isOutgoing: Bool {
        if let isSender = message.isSender {
            return isSender
        }

        if let currentParticipant {
            return message.senderID == currentParticipant.id
        }

        return false
    }

    private var groupedReactions: [GroupedReaction]? {
        guard let reactions = message.reactions, reactions.isEmpty == false else {
            return nil
        }

        var groups: [String: GroupedReaction] = [:]
        for reaction in reactions {
            if var existing = groups[reaction.reactionKey] {
                existing.count += 1
                existing.participantIDs.append(reaction.participantID)
                groups[reaction.reactionKey] = existing
            } else {
                groups[reaction.reactionKey] = GroupedReaction(
                    reactionKey: reaction.reactionKey,
                    count: 1,
                    participantIDs: [reaction.participantID]
                )
            }
        }

        return groups.values.sorted(by: { $0.reactionKey < $1.reactionKey })
    }

    private func hasOwnReaction(for reactionKey: String) -> Bool {
        guard let participantID = currentParticipant?.id else { return false }
        return message.reactions?.contains(where: { $0.reactionKey == reactionKey && $0.participantID == participantID }) == true
    }
}

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
                    .background(isOwn ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15))
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

private struct ReplyPreviewView: View {
    @Environment(ChatStore.self) private var chatStore

    let linkedMessageID: String
    let chatID: String
    let isOutgoing: Bool

    var body: some View {
        let linkedMessage = chatStore.message(byID: linkedMessageID, in: chatID)

        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.accentColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(linkedMessage?.senderDisplayName ?? "Unknown")
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.secondary)

                Text(linkedMessage?.displayText ?? "Original message")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isOutgoing ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8))
    }
}

#Preview {
    VStack {
        MessageRowView(message: Message(
            id: "msg-1",
            chatID: "chat-1",
            senderID: "@alice",
            senderName: "Alice",
            timestamp: .now,
            sortKey: "1",
            type: nil,
            text: "Hello",
            isSender: false,
            attachments: nil,
            reactions: nil,
            linkedMessageID: nil
        ), chat: Chat(
            id: "chat-1",
            title: "General",
            unreadCount: 0,
            participants: nil,
            preview: nil,
            isMuted: nil,
            type: "group",
            isPinned: nil,
            isArchived: nil,
            accountID: nil,
            lastActivity: nil,
            lastReadMessageSortKey: nil
        ))

        MessageRowView(message: Message(
            id: "msg-2",
            chatID: "chat-1",
            senderID: "@me",
            senderName: "Me",
            timestamp: .now,
            sortKey: "2",
            type: nil,
            text: "Hey!",
            isSender: true,
            attachments: nil,
            reactions: nil,
            linkedMessageID: nil
        ), chat: Chat(
            id: "chat-1",
            title: "General",
            unreadCount: 0,
            participants: nil,
            preview: nil,
            isMuted: nil,
            type: "group",
            isPinned: nil,
            isArchived: nil,
            accountID: nil,
            lastActivity: nil,
            lastReadMessageSortKey: nil
        ))
    }
    .padding()
}
