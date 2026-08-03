import Foundation

enum OutgoingMessageState: Equatable {
    case sending
    case failed(String)
}

/// A client-owned timeline item that exists immediately after Send is tapped.
/// It remains independent from the currently selected chat while the remote
/// server accepts the message and any attachments.
struct OutgoingMessage: Identifiable, Equatable {
    let id: UUID
    let chatID: String
    let text: String
    let attachments: [PendingAttachment]
    let replyToMessageID: String?
    let createdAt: Date
    var state: OutgoingMessageState
    var uploadProgressByAttachmentID: [PendingAttachment.ID: Double]
    var uploadFileNameByAttachmentID: [PendingAttachment.ID: String]
    var uploadMimeTypeByAttachmentID: [PendingAttachment.ID: String]
    var pendingMessageIDs: Set<String>
    var confirmedMessageIDs: Set<String>

    init(
        id: UUID = UUID(),
        chatID: String,
        text: String,
        attachments: [PendingAttachment],
        replyToMessageID: String?,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.chatID = chatID
        self.text = text
        self.attachments = attachments
        self.replyToMessageID = replyToMessageID
        self.createdAt = createdAt
        self.state = .sending
        self.uploadProgressByAttachmentID = [:]
        self.uploadFileNameByAttachmentID = [:]
        self.uploadMimeTypeByAttachmentID = [:]
        self.pendingMessageIDs = []
        self.confirmedMessageIDs = []
    }

    var timelineKey: String { "outgoing-\(id.uuidString)" }

    /// Changes only when this row starts or stops suppressing its canonical
    /// counterpart, allowing timeline caches to invalidate without reacting to
    /// every upload-progress update.
    var suppressionID: ID? {
        guard case .sending = state else { return nil }
        return id
    }

    var expectedConfirmationCount: Int {
        max(attachments.count, 1)
    }

    /// Whether a canonical timeline message is the server-confirmed form of this
    /// optimistic row. This check is active from the moment the row is created,
    /// so a fast WebSocket event cannot briefly render alongside it.
    func suppressesConfirmedMessage(_ message: Message) -> Bool {
        guard case .sending = state else { return false }
        return matchesConfirmedMessage(message)
    }

    /// Whether a canonical message is the server-confirmed form of this row.
    /// Matching remains active after a transport failure because the server may
    /// have committed the send before its acknowledgement was lost.
    func matchesConfirmedMessage(_ message: Message) -> Bool {
        guard message.chatID == chatID,
              message.isSender == true,
              message.timestamp >= createdAt.addingTimeInterval(-60),
              message.timestamp <= createdAt.addingTimeInterval(60 * 60)
        else { return false }

        if let transactionID = message.transactionID,
           pendingMessageIDs.contains(transactionID) {
            return true
        }

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
