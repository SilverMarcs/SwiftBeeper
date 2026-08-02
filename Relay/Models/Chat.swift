import Foundation

struct ChatParticipant: Identifiable, Decodable, Equatable {
    let id: String
    let username: String?
    let fullName: String?
    let imgURL: String?
    let isSelf: Bool?
    let cannotMessage: Bool?

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

struct ChatParticipants: Decodable, Equatable {
    let items: [ChatParticipant]
    let hasMore: Bool?
    let total: Int?
}

enum ChatKind: RawRepresentable, Decodable, Equatable {
    case single
    case group
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "single":
            self = .single
        case "group":
            self = .group
        default:
            self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .single:
            return "single"
        case .group:
            return "group"
        case .unknown(let value):
            return value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = ChatKind(rawValue: try container.decode(String.self))
    }
}

struct Chat: Identifiable, Decodable, Equatable {
    let id: String
    var title: String
    var unreadCount: Int
    var participants: ChatParticipants?
    var preview: Message?
    var isMuted: Bool?
    var type: ChatKind?
    var isPinned: Bool?
    var isArchived: Bool?
    var isLowPriority: Bool?
    var isMarkedUnread: Bool? = nil
    var accountID: String?
    var lastActivity: Date?
    var lastReadMessageSortKey: String?
    var imgURL: String?

    var isSingleChat: Bool { type == .single }
    var isGroupChat: Bool { type == .group }

    var displayTitle: String {
        title.isEmpty ? "Untitled Chat" : title
    }

    var previewText: String? {
        preview?.displayText
    }

    var otherParticipant: ChatParticipant? {
        participants?.items.first(where: { $0.isSelf != true })
    }

    var cannotMessage: Bool {
        guard isSingleChat else { return false }
        return otherParticipant?.cannotMessage == true
    }

    func participant(with id: String) -> ChatParticipant? {
        participants?.items.first(where: { $0.id == id })
    }

    /// Merges a freshly-fetched copy (`detail`) into this one. `detail` wins for
    /// most fields, but we preserve richer data this copy may already hold.
    func merging(detail: Chat) -> Chat {
        var result = detail

        // The list endpoint can return a non-nil but truncated `participants`
        // (it doesn't pass `maxParticipantCount=-1`), so keep whichever side has
        // more so fully-hydrated group avatars survive a list refresh.
        if let existing = participants,
           (detail.participants?.items.count ?? 0) < existing.items.count {
            result.participants = existing
        }

        // Keep the newest preview by sort key so the sidebar always reflects the
        // most recent activity, regardless of which fetch arrived last.
        if let existing = preview,
           (detail.preview?.numericSortKey ?? .min) < existing.numericSortKey {
            result.preview = existing
        }

        // Fall back to existing values for optional fields the refresh omitted.
        result.isMuted = detail.isMuted ?? isMuted
        result.type = detail.type ?? type
        result.isPinned = detail.isPinned ?? isPinned
        result.isArchived = detail.isArchived ?? isArchived
        result.isLowPriority = detail.isLowPriority ?? isLowPriority
        result.isMarkedUnread = detail.isMarkedUnread ?? isMarkedUnread
        result.accountID = detail.accountID ?? accountID
        result.lastActivity = detail.lastActivity ?? lastActivity
        result.lastReadMessageSortKey = detail.lastReadMessageSortKey ?? lastReadMessageSortKey
        result.imgURL = detail.imgURL ?? imgURL

        return result
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
