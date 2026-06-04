import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MessageRowView: View {
    @Environment(ChatStore.self) private var chatStore

    let message: Message
    let chat: Chat
    /// Whether to show the "Read" indicator below this outgoing message.
    /// Only the last consecutive outgoing message that's been read should show this.
    var showReadIndicator: Bool = false
    var isFirstInGroup: Bool = true
    var isLastInGroup: Bool = true
    var onTapLinkedMessage: ((String) -> Void)? = nil

    @State private var profileSheetParticipant: ChatParticipant?

    private static let commonReactions = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

    var body: some View {
        let isOutgoing = message.isOutgoing(in: chat)
        HStack(alignment: .bottom, spacing: 6) {
            if isOutgoing {
                Spacer(minLength: 50)
            } else if showIncomingIdentity {
                if isLastInGroup {
                    Button {
                        if let participant = chat.participant(with: message.senderID) {
                            profileSheetParticipant = participant
                        }
                    } label: {
                        ProfileAvatarView(name: message.senderDisplayName, imageURLString: senderAvatarImageURL, dimension: 28)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                        .frame(width: 28, height: 1)
                }
            }

            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
                if !isOutgoing && showIncomingIdentity && isFirstInGroup {
                    Text(message.senderDisplayName)
                        .font(.subheadline)
                        .bold()
                }

                if let linkedMessageID = message.linkedMessageID, !linkedMessageID.isEmpty {
                    ReplyPreviewView(
                        linkedMessageID: linkedMessageID,
                        chatID: message.chatID,
                        isOutgoing: isOutgoing,
                        onTap: { onTapLinkedMessage?(linkedMessageID) }
                    )
                }

                messageContent

                if isOutgoing && showReadIndicator {
                   Text("Read")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 3)
                }
            }

            if !isOutgoing {
                Spacer(minLength: 50)
            }
        }
        .sheet(item: $profileSheetParticipant) { participant in
            ParticipantProfileSheet(participant: participant)
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
                            await chatStore.removeReaction(from: message.id, in: message.chatID, reactionKey: reactionKey)
                        } else {
                            await chatStore.addReaction(to: message.id, in: message.chatID, reactionKey: reactionKey)
                        }
                    }
                }
            )
        }
    }

    private enum BubbleSlot: Equatable {
        case attachment(String?)
        case textWithUrls
        case linkPill(String)
        case text
    }

    private var lastBubbleSlot: BubbleSlot? {
        if let urls = message.extractedURLs, let last = urls.last {
            return .linkPill(last.absoluteString)
        }
        if message.hasText || message.isEmptyDeleted { return .text }
        if let attachments = message.attachments, let last = attachments.last {
            return .attachment(last.id)
        }
        return nil
    }

    @ViewBuilder
    private func reactionsOverlay(if slot: BubbleSlot) -> some View {
        if slot == lastBubbleSlot {
            reactionsView
                .offset(
                    x: message.isOutgoing(in: chat) ? -15 : 15,
                    y: 1
                )
        }
    }

    private var reactionsAlignment: Alignment {
        message.isOutgoing(in: chat) ? .bottomLeading : .bottomTrailing
    }

    @ViewBuilder
    private var messageContent: some View {
        let isOutgoing = message.isOutgoing(in: chat)
        VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
            if let attachments = message.attachments, attachments.isEmpty == false {
                ForEach(attachments) { attachment in
                    AttachmentView(attachment: attachment, isOutgoing: isOutgoing)
                        .overlay(alignment: reactionsAlignment) {
                            reactionsOverlay(if: .attachment(attachment.id))
                        }
                }
            }

            if let urls = message.extractedURLs, !urls.isEmpty {
                if message.textWithoutURLs?.isEmpty == false {
                    Text(message.textWithoutURLs!.markdownAttributed)
                        .foregroundStyle(isOutgoing ? .white : .primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .messageBubbleChrome(isOutgoing: isOutgoing)
                        .overlay(alignment: reactionsAlignment) {
                            reactionsOverlay(if: .textWithUrls)
                        }
                }

                ForEach(urls, id: \.absoluteString) { url in
                    LinkPillView(url: url)
                        .overlay(alignment: reactionsAlignment) {
                            reactionsOverlay(if: .linkPill(url.absoluteString))
                        }
                }
            } else if message.hasText || message.isEmptyDeleted {
                Group {
                    if message.isEmptyDeleted {
                        Label(message.displayText, systemImage: "trash")
                            .italic()
                    } else {
                        Text(message.displayText.markdownAttributed)
                    }
                }
                .foregroundStyle(isOutgoing ? .white : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .messageBubbleChrome(isOutgoing: isOutgoing)
                .overlay(alignment: reactionsAlignment) {
                    reactionsOverlay(if: .text)
                }
            }
        }
        #if !os(macOS)
        .contentShape(.contextMenuPreview, .rect(cornerRadius: 16))
        #endif
        .contextMenu {
            contextMenuItems
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Section {
            EmptyView()
        } header: {
            Text(message.timestampText)
        }

        Picker(selection: Binding<String?>(
            get: { ownReactionKey },
            set: { newValue in
                let old = ownReactionKey
                Task {
                    if let old, old != newValue {
                        await chatStore.removeReaction(from: message.id, in: message.chatID, reactionKey: old)
                    }
                    if let newValue, newValue != old {
                        await chatStore.addReaction(to: message.id, in: message.chatID, reactionKey: newValue)
                    }
                }
            }
        )) {
           #if os(macOS)
            Text("None").tag(String?.none)
            #endif
            ForEach(Self.commonReactions, id: \.self) { emoji in
                Text(emoji).tag(String?.some(emoji))
            }
        } label: {
                        #if os(macOS)
            Label("Reactions", systemImage: "face.smiling.inverse")

                .labelStyle(.titleAndIcon)
             #endif
        }
        .pickerStyle(.palette)

        Divider()

        Button {
            withAnimation {
                chatStore.setReplyTo(message)
            }
        } label: {
            Label("Reply", systemImage: "arrowshape.turn.up.left")
        }

        if message.hasText || message.isEmptyDeleted {
            Button {
                copyMessageText()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }

        if chatStore.canEdit(message, in: chat) {
            Button {
                withAnimation {
                    chatStore.startEditing(message, in: chat)
                }
            } label: {
                Label("Edit", systemImage: "pencil")
            }
        }

        if let attachments = message.attachments, !attachments.isEmpty {
            Divider()
            ForEach(attachments) { attachment in
                Button {
                    Task { await saveAttachmentToDownloads(attachment) }
                } label: {
                    Label(saveLabel(for: attachment, totalCount: attachments.count), systemImage: "arrow.down")
                }
            }
        }

        if !message.isEmptyDeleted && message.isOutgoing(in: chat) {
            Divider()
            Button(role: .destructive) {
                Task {
                    await chatStore.deleteMessage(message.id, in: message.chatID)
                }
            } label: {
                Label("Delete", systemImage: "trash")
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

    private var ownReactionKey: String? {
        guard let participantID = currentParticipant?.id else { return nil }
        return message.reactions?.first(where: { $0.participantID == participantID })?.reactionKey
    }

    private func copyMessageText() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.displayText, forType: .string)
        #else
        UIPasteboard.general.string = message.displayText
        #endif
    }

    private func saveLabel(for attachment: Attachment, totalCount: Int) -> String {
        // if totalCount > 1, let name = attachment.fileName, !name.isEmpty {
            // return "Save \"\(name)\" to Downloads"
        // }
        // return "Save \(attachment.typeLabel) to Downloads"
        return "Save to Downloads"
    }

    private func saveAttachmentToDownloads(_ attachment: Attachment) async {
        guard let urlString = attachment.resolvedURL,
              let request = AuthenticatedImageLoader.buildRequest(for: urlString) else { return }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }

            guard let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }

            let destination = uniqueDestination(in: downloadsDir, for: attachment)
            try data.write(to: destination)
        } catch {
            // Silently ignore; user can retry.
        }
    }

    private func uniqueDestination(in directory: URL, for attachment: Attachment) -> URL {
        let proposedName = attachment.fileName?.isEmpty == false
            ? attachment.fileName!
            : defaultFileName(for: attachment)

        let baseURL = directory.appending(path: proposedName)
        let fm = FileManager.default
        guard fm.fileExists(atPath: baseURL.path) else { return baseURL }

        let stem = baseURL.deletingPathExtension().lastPathComponent
        let ext = baseURL.pathExtension
        var index = 2
        while true {
            let candidateName = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
            let candidate = directory.appending(path: candidateName)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    private func defaultFileName(for attachment: Attachment) -> String {
        let ext = (attachment.resolvedURL.flatMap(URL.init(string:))?.pathExtension) ?? ""
        let base = "beeper-\(attachment.typeLabel)-\(Int(Date().timeIntervalSince1970))"
        return ext.isEmpty ? base : "\(base).\(ext)"
    }
}
