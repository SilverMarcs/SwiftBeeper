import Foundation

struct ListChatsOutput: Decodable {
    let items: [Chat]
    let hasMore: Bool?
    let oldestCursor: String?
    let newestCursor: String?
}

struct SearchChatsOutput: Decodable {
    let items: [Chat]
    let hasMore: Bool
    let oldestCursor: String?
    let newestCursor: String?
}

struct ListMessagesOutput: Decodable {
    let items: [Message]
    let hasMore: Bool
}

struct SendMessageOutput: Decodable {
    let chatID: String
    let pendingMessageID: String
}

struct EditMessageOutput: Decodable {
    let chatID: String
    let messageID: String
    let success: Bool
}

struct AddReactionOutput: Decodable {
    let success: Bool
    let chatID: String
    let messageID: String
    let reactionKey: String
    let transactionID: String
}

struct RemoveReactionOutput: Decodable {
    let success: Bool
    let chatID: String
    let messageID: String
    let reactionKey: String
}

struct ChatParticipant: Identifiable, Decodable {
    let id: String
    let username: String?
    let fullName: String?
    let imgURL: String?
    let isSelf: Bool?

    var displayName: String {
        if let fullName, fullName.isEmpty == false {
            return fullName
        }
        if let username, username.isEmpty == false {
            return username
        }
        return id
    }
}

struct ChatParticipants: Decodable {
    let items: [ChatParticipant]
    let hasMore: Bool?
    let total: Int?
}

struct Chat: Identifiable, Decodable {
    let id: String
    let title: String
    let unreadCount: Int
    let participants: ChatParticipants?
    let preview: Message?
    let isMuted: Bool?
    let type: String?
    let isPinned: Bool?
    let isArchived: Bool?
    let accountID: String?
    let lastActivity: Date?
    let lastReadMessageSortKey: String?

    // TODO: use enum or boolean
    var isSingleChat: Bool { type == "single" }
    var isGroupChat: Bool { type == "group" }

    var displayTitle: String {
        title.isEmpty ? "Untitled Chat" : title
    }

    var previewText: String? {
        preview?.displayText
    }

    var otherParticipant: ChatParticipant? {
        participants?.items.first(where: { $0.isSelf != true })
    }

    func participant(with id: String) -> ChatParticipant? {
        participants?.items.first(where: { $0.id == id })
    }

    /// Merge detail-endpoint data into an existing chat, preserving fields the detail response may omit (e.g. preview).
    func merging(detail: Chat) -> Chat {
        Chat(
            id: id,
            title: detail.title,
            unreadCount: detail.unreadCount,
            participants: detail.participants ?? participants,
            preview: preview ?? detail.preview,
            isMuted: detail.isMuted ?? isMuted,
            type: detail.type ?? type,
            isPinned: detail.isPinned ?? isPinned,
            isArchived: detail.isArchived ?? isArchived,
            accountID: detail.accountID ?? accountID,
            lastActivity: detail.lastActivity ?? lastActivity,
            lastReadMessageSortKey: detail.lastReadMessageSortKey ?? lastReadMessageSortKey
        )
    }

    var lastActivityText: String? {
        guard let lastActivity else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(lastActivity) {
            return lastActivity.formatted(date: .omitted, time: .shortened)
        } else if calendar.isDateInYesterday(lastActivity) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: lastActivity, to: .now).day, daysAgo < 7 {
            return lastActivity.formatted(.dateTime.weekday(.abbreviated))
        } else {
            return lastActivity.formatted(date: .numeric, time: .omitted)
        }
    }
}

struct AttachmentSize: Decodable {
    let width: Int?
    let height: Int?
}

struct Attachment: Identifiable, Decodable {
    var id: String? { _id ?? srcURL ?? fileName }

    let type: String
    let srcURL: String?
    let mimeType: String?
    let fileName: String?
    let fileSize: Int?
    let isGif: Bool?
    let isSticker: Bool?
    let isVoiceNote: Bool?
    let duration: Double?
    let posterImg: String?
    let size: AttachmentSize?

    private let _id: String?

    private enum CodingKeys: String, CodingKey {
        case _id = "id"
        case type, srcURL, mimeType, fileName, fileSize
        case isGif, isSticker, isVoiceNote, duration, posterImg, size
    }

    var isImage: Bool { type == "img" }
    var isVideo: Bool { type == "video" }
    var isAudio: Bool { type == "audio" }

    /// The best URL to use for loading this attachment's content.
    var resolvedURL: String? {
        srcURL ?? _id
    }

    var typeLabel: String {
        if isImage { return "image" }
        if isVideo { return "video" }
        if isAudio { return "audio" }
        return "file"
    }
}

struct Reaction: Codable, Identifiable, Hashable {
    let id: String
    let reactionKey: String
    let imgURL: String?
    let participantID: String
    let emoji: Bool?
}

struct Message: Identifiable, Decodable {
    let id: String
    let chatID: String
    let senderID: String
    let senderName: String?
    let timestamp: Date
    let sortKey: String
    let text: String?
    let isSender: Bool?
    let attachments: [Attachment]?
    let reactions: [Reaction]?
    let linkedMessageID: String?

    var senderDisplayName: String {
        if let senderName, senderName.isEmpty == false {
            return senderName
        }
        return senderID
    }

    var displayText: String {
        let text = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let text, text.isEmpty == false {
            return text
        }

        if let attachments, let first = attachments.first {
            return "Sent \(attachments.count > 1 ? "\(attachments.count) attachments" : "an \(first.typeLabel)")"
        }

        return "(No text)"
    }

    var isEmptyDeleted: Bool {
        !hasText && (attachments ?? []).isEmpty
    }

    var hasText: Bool {
        if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), text.isEmpty == false {
            return true
        }
        return false
    }

    var timestampText: String {
        timestamp.formatted(date: .abbreviated, time: .shortened)
    }
}
