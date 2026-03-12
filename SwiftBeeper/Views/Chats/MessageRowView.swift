import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct MessageRowView: View {
    @Environment(MessageStore.self) private var messageStore

    let message: Message
    let chat: Chat

    private static let commonReactions = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

    var body: some View {
        HStack(alignment: .top) {
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
                        .foregroundStyle(isOutgoing ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(ChatVisualStyle.bubbleFill(isOutgoing: isOutgoing))
                        .clipShape(.rect(cornerRadius: 15))
                }

                if let groupedReactions = groupedReactions, groupedReactions.isEmpty == false {
                    ReactionsBarView(
                        groupedReactions: groupedReactions,
                        currentParticipantID: currentParticipant?.id,
                        onToggle: { reactionKey, isOwn in
                            Task {
                                if isOwn {
                                    await messageStore.removeReaction(from: message.id, in: message.chatID, reactionKey: reactionKey)
                                } else {
                                    await messageStore.addReaction(to: message.id, in: message.chatID, reactionKey: reactionKey)
                                }
                            }
                        }
                    )
                }
            }
            .contextMenu {
                Section {
                    EmptyView()
                } header: {
                    Text(message.timestampText)
                }

                ControlGroup {
                    ForEach(Self.commonReactions, id: \.self) { emoji in
                        Button {
                            Task {
                                if hasOwnReaction(for: emoji) {
                                    await messageStore.removeReaction(from: message.id, in: message.chatID, reactionKey: emoji)
                                } else {
                                    await messageStore.addReaction(to: message.id, in: message.chatID, reactionKey: emoji)
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
                    withAnimation {
                        messageStore.setReplyTo(message)
                    }
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }

                if message.hasText {
                    Button {
                        copyMessageText()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }

                if messageStore.canEdit(message, in: chat) {
                    Button {
                        withAnimation {
                            messageStore.startEditing(message, in: chat)
                        }
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                }

            }

            if isOutgoing == false {
                Spacer(minLength: 100)
            }
        }
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

    private func copyMessageText() {
#if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.displayText, forType: .string)
#elseif canImport(UIKit)
        UIPasteboard.general.string = message.displayText
#endif
    }
}
