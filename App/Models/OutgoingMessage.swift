import Foundation

enum OutgoingMessageState: Equatable {
    case sending
    case failed(String)
}

/// A client-owned timeline item that exists immediately after Send is tapped.
/// It remains independent from the currently selected chat while the Matrix
/// core accepts the message and any attachments.
struct OutgoingMessage: Identifiable, Equatable {
    let id: UUID
    let chatID: String
    let text: String
    let mentions: [ComposerMention]
    let attachments: [PendingAttachment]
    let replyToMessageID: String?
    /// The thread this message replies in, if any.
    let threadRootID: String?
    /// Whether a thread reply also goes to the main timeline.
    let alsoSendToChat: Bool
    let createdAt: Date
    var state: OutgoingMessageState = .sending
    var uploadFileNameByAttachmentID: [PendingAttachment.ID: String] = [:]
    var uploadMimeTypeByAttachmentID: [PendingAttachment.ID: String] = [:]
    var pendingMessageIDs: Set<String> = []
    var confirmedMessageIDs: Set<String> = []

    init(
        id: UUID = UUID(),
        chatID: String,
        text: String,
        mentions: [ComposerMention] = [],
        attachments: [PendingAttachment],
        replyToMessageID: String?,
        threadRootID: String? = nil,
        alsoSendToChat: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.chatID = chatID
        self.text = text
        self.mentions = mentions
        self.attachments = attachments
        self.replyToMessageID = replyToMessageID
        self.threadRootID = threadRootID
        self.alsoSendToChat = alsoSendToChat
        self.createdAt = createdAt
    }

    var timelineKey: String { "outgoing-\(id.uuidString)" }

    /// Whether the main timeline shows this row: anything but a thread reply
    /// kept to its thread.
    var showsInMainTimeline: Bool { threadRootID == nil || alsoSendToChat }

    /// The thread a reply also sent to the chat goes to; nil for any other send.
    var broadcastThreadRootID: String? { alsoSendToChat ? threadRootID : nil }

    /// One confirmed message per attachment, or one for a text-only send.
    var expectedConfirmationCount: Int {
        max(attachments.count, 1)
    }

    /// Whether a canonical message is the homeserver-confirmed form of this row.
    /// Matching remains active after a send failure because the homeserver may
    /// have committed the send before its acknowledgement was lost.
    func matchesConfirmedMessage(_ message: Message) -> Bool {
        guard message.chatID == chatID,
              message.isSender,
              message.timestamp >= createdAt.addingTimeInterval(-60),
              message.timestamp <= createdAt.addingTimeInterval(60 * 60)
        else { return false }

        if let transactionID = message.transactionID,
           pendingMessageIDs.contains(transactionID) {
            return true
        }

        // Without a transaction ID, the same text in the main timeline and in
        // a thread are different messages.
        guard message.threadRootID == threadRootID else { return false }

        if attachments.isEmpty {
            return message.text?.trimmed == text
        }

        guard let confirmedAttachments = message.attachments else { return false }
        return attachments.contains { pending in
            confirmedAttachments.contains { confirmed in
                let uploadFileName = uploadFileNameByAttachmentID[pending.id]
                guard confirmed.fileName == pending.fileName || confirmed.fileName == uploadFileName else {
                    return false
                }
                let uploadMimeType = uploadMimeTypeByAttachmentID[pending.id]
                return confirmed.mimeType == nil
                    || confirmed.mimeType == pending.mimeType
                    || confirmed.mimeType == uploadMimeType
            }
        }
    }
}
