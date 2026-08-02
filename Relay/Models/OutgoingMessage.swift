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
        guard case .sending = state,
              message.chatID == chatID,
              message.isSender == true,
              message.timestamp >= createdAt.addingTimeInterval(-60)
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
                guard confirmed.fileName == pending.fileName else { return false }
                return confirmed.mimeType == nil || confirmed.mimeType == pending.mimeType
            }
        }
    }
}
