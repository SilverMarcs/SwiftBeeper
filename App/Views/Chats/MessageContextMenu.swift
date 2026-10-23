import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Reactions, reply, copy, edit, save, and delete for one message.
struct MessageContextMenu: View {
    @Environment(ChatStore.self) private var chatStore

    let message: Message
    let chat: Chat

    private static let commonReactions = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

    var body: some View {
        Section {
            EmptyView()
        } header: {
            Text(message.timestampText)
        }

        Picker(selection: Binding(get: { ownReactionKey }, set: setOwnReaction)) {
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
        #if !os(macOS)
        .pickerStyle(.palette)
        #endif

        Section {
            Button("Reply", systemImage: "arrowshape.turn.up.left") {
                withAnimation {
                    chatStore.setReplyTo(message)
                }
            }

            if message.hasText || message.isDeletedMessage {
                Button("Copy", systemImage: "doc.on.doc", action: copyMessageText)
            }

            if chatStore.canEdit(message, in: chat) {
                Button("Edit", systemImage: "pencil") {
                    withAnimation {
                        chatStore.startEditing(message, in: chat)
                    }
                }
            }
        } header: {
            #if !os(macOS)
            Text(message.timestampText)
            #endif
        }

        if let attachments = message.attachments, !attachments.isEmpty {
            Divider()
            ForEach(attachments) { attachment in
                Button("Save to Downloads", systemImage: "arrow.down") {
                    Task { await saveToDownloads(attachment) }
                }
            }
        }

        if !message.isDeletedMessage && message.isSender {
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task {
                    await chatStore.deleteMessage(message.id, in: message.chatID)
                }
            }
        }
    }

    private var ownReactionKey: String? {
        guard let selfID = chat.participants?.items.first(where: { $0.isSelf == true })?.id else { return nil }
        return message.reactions?.first { $0.participantID == selfID }?.reactionKey
    }

    private func setOwnReaction(_ newValue: String?) {
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

    private func copyMessageText() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.displayText, forType: .string)
        #else
        UIPasteboard.general.string = message.displayText
        #endif
    }

    private func saveToDownloads(_ attachment: Attachment) async {
        guard let source = attachment.resolvedURL,
              let file = await MatrixMedia.localFile(for: source) else { return }
        // A file copy clones on APFS instead of reading the media into memory.
        // Failures are silently ignored; the user can retry.
        try? FileManager.default.copyItem(at: file, to: uniqueDownloadsURL(for: attachment))
    }

    private func uniqueDownloadsURL(for attachment: Attachment) -> URL {
        let directory = URL.downloadsDirectory
        let proposedName = attachment.fileName.flatMap { $0.isEmpty ? nil : $0 }
            ?? "beeper-\(attachment.typeLabel)-\(Int(Date().timeIntervalSince1970))"

        let baseURL = directory.appending(path: proposedName)
        guard FileManager.default.fileExists(atPath: baseURL.path) else { return baseURL }

        let stem = baseURL.deletingPathExtension().lastPathComponent
        let ext = baseURL.pathExtension
        var index = 2
        while true {
            let candidateName = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
            let candidate = directory.appending(path: candidateName)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }
}
