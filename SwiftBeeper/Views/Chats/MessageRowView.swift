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
            if message.isOutgoing(in: chat) {
                Spacer(minLength: 100)
            } else if showIncomingIdentity {
                ProfileAvatarView(name: message.senderDisplayName, imageURLString: senderAvatarImageURL, dimension: 28)
            }

            VStack(alignment: message.isOutgoing(in: chat) ? .trailing : .leading, spacing: 4) {
                if !message.isOutgoing(in: chat) && showIncomingIdentity {
                    Text(message.senderDisplayName)
                        .font(.subheadline)
                        .bold()
                }

                if let linkedMessageID = message.linkedMessageID {
                    ReplyPreviewView(
                        linkedMessageID: linkedMessageID,
                        chatID: message.chatID,
                        isOutgoing: message.isOutgoing(in: chat)
                    )
                }

                if let attachments = message.attachments, attachments.isEmpty == false {
                    ForEach(attachments) { attachment in
                        AttachmentView(attachment: attachment, isOutgoing: message.isOutgoing(in: chat))
                    }
                }

                if message.hasText {
                    Text(message.displayText.markdownAttributed)
                        .foregroundStyle(message.isOutgoing(in: chat) ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(ChatVisualStyle.bubbleFill(isOutgoing: message.isOutgoing(in: chat)))
                        .clipShape(.rect(cornerRadius: 15))
                }

                if let groupedReactions = message.groupedReactions, groupedReactions.isEmpty == false {
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

            if !message.isOutgoing(in: chat) {
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
