import Foundation

struct ChatParticipant: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let username: String?
    let fullName: String?
    let imgURL: String?
    let isSelf: Bool?

    var displayName: String {
        if let fullName, !fullName.isEmpty { return fullName }
        if let username, !username.isEmpty { return username }
        return id
    }
}

struct ChatParticipants: Codable, Equatable, Sendable {
    let items: [ChatParticipant]
    let hasMore: Bool?
    let total: Int?
}

/// The core's chat type, keeping values this app doesn't know.
enum ChatKind: RawRepresentable, Codable, Equatable, Sendable {
    case single
    case group
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "single": self = .single
        case "group": self = .group
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .single: "single"
        case .group: "group"
        case .unknown(let value): value
        }
    }

    init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct Chat: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var title: String
    var unreadCount: Int
    /// Whether an unread message mentions the user.
    var hasUnreadMention: Bool?
    var participants: ChatParticipants?
    var preview: Message?
    var isMuted: Bool?
    var isPinned: Bool?
    var pinOrder: Double?
    var type: ChatKind?
    var isArchived: Bool?
    var isMarkedUnread: Bool?
    var accountID: String?
    var lastActivity: Date?
    var lastReadMessageSortKey: String?
    var imgURL: String?

    var isSingleChat: Bool { type == .single }
    var isGroupChat: Bool { type == .group }

    var displayTitle: String {
        title.isEmpty ? "Untitled Chat" : title
    }

    /// Preview source, preferring the formatted body so the row can render
    /// the same inline Markdown as the timeline.
    var previewText: String? {
        guard let preview else { return nil }
        if preview.hasText, let formattedText = preview.formattedText, !formattedText.isEmpty {
            return formattedText
        }
        return preview.displayText
    }

    /// SF Symbol for the preview's attachments, shown before the caption or
    /// attachment summary. Nil for text-only and deleted messages.
    var previewSymbol: String? {
        guard let preview, !preview.isDeletedMessage else { return nil }
        return preview.attachmentSymbol
    }

    /// The sender label shown before the preview: "You: " for the user's own
    /// messages in any chat, otherwise the sender's first name in group chats.
    var previewSenderPrefix: String {
        guard let preview else { return "" }
        if preview.isSender { return "You: " }
        guard isGroupChat else { return "" }
        guard let firstName = preview.senderDisplayName.split(whereSeparator: \.isWhitespace).first else { return "" }
        return "\(firstName): "
    }

    var otherParticipant: ChatParticipant? {
        participants?.items.first(where: { $0.isSelf != true })
    }

    /// The chat's own image, if it has one.
    var ownImageURL: String? {
        guard let url = imgURL?.trimmed, !url.isEmpty else { return nil }
        return url
    }

    /// The chat's own image, or the other person's outside group chats.
    var avatarURL: String? {
        ownImageURL ?? (isGroupChat ? nil : otherParticipant?.imgURL)
    }

    func participant(with id: String) -> ChatParticipant? {
        participants?.items.first(where: { $0.id == id })
    }

    var lastActivityText: String? {
        guard let lastActivity else { return nil }
        let calendar = Calendar.app
        if calendar.isDateInToday(lastActivity) {
            return lastActivity.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(lastActivity) {
            return "Yesterday"
        }
        if let daysAgo = calendar.dateComponents([.day], from: lastActivity, to: .now).day, daysAgo < 7 {
            return lastActivity.formatted(.dateTime.weekday(.abbreviated))
        }
        return lastActivity.formatted(date: .numeric, time: .omitted)
    }
}
