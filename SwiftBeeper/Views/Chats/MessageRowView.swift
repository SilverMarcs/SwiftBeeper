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
    /// Whether to show the "Read" indicator below this outgoing message.
    /// Only the last consecutive outgoing message that's been read should show this.
    var showReadIndicator: Bool = false
    var isFirstInGroup: Bool = true
    var isLastInGroup: Bool = true

    private static let commonReactions = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.isOutgoing(in: chat) {
                Spacer(minLength: 100)
            } else if showIncomingIdentity {
                if isLastInGroup {
                    ProfileAvatarView(name: message.senderDisplayName, imageURLString: senderAvatarImageURL, dimension: 28)
                } else {
                    Color.clear
                        .frame(width: 28, height: 1)
                }
            }

            VStack(alignment: message.isOutgoing(in: chat) ? .trailing : .leading, spacing: 4) {
                if !message.isOutgoing(in: chat) && showIncomingIdentity && isFirstInGroup {
                    Text(message.senderDisplayName)
                        .font(.subheadline)
                        .bold()
                }

                if let linkedMessageID = message.linkedMessageID, !linkedMessageID.isEmpty {
                    ReplyPreviewView(
                        linkedMessageID: linkedMessageID,
                        chatID: message.chatID,
                        isOutgoing: message.isOutgoing(in: chat)
                    )
                }

                messageContent
                    .overlay(alignment: message.isOutgoing(in: chat) ? .bottomLeading : .bottomTrailing) {
                        reactionsView
                            .offset(
                                x: message.isOutgoing(in: chat) ? -15 : 15,
                                y: 1
                            )
                    }

                if message.isOutgoing(in: chat) && showReadIndicator {
                   Text("Read")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 3)
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

    @ViewBuilder
    private var reactionsView: some View {
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

    @ViewBuilder
    private var messageContent: some View {
        VStack(alignment: message.isOutgoing(in: chat) ? .trailing : .leading, spacing: 4) {
            if let attachments = message.attachments, attachments.isEmpty == false {
                ForEach(attachments) { attachment in
                    AttachmentView(attachment: attachment, isOutgoing: message.isOutgoing(in: chat))
                }
            }

            if let urls = message.extractedURLs, !urls.isEmpty {
                if message.textWithoutURLs?.isEmpty == false {
                    Text(message.textWithoutURLs!.markdownAttributed)
                        .foregroundStyle(message.isOutgoing(in: chat) ? .white : .primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .bubbleBackground(isOutgoing: message.isOutgoing(in: chat))
                        .clipShape(.rect(cornerRadius: 15))
                }

                ForEach(urls, id: \.absoluteString) { url in
                    LinkPillView(url: url)
                }
            } else if message.hasText {
                Text(message.displayText.markdownAttributed)
                    .foregroundStyle(message.isOutgoing(in: chat) ? .white : .primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .bubbleBackground(isOutgoing: message.isOutgoing(in: chat))
                    .clipShape(.rect(cornerRadius: 15))
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
