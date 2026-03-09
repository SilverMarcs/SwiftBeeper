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
    let title: String
    let unreadCount: Int
    let participants: ChatParticipants?
    let preview: Message?
    let isMuted: Bool?
    let type: ChatKind?
    let isPinned: Bool?
    let isArchived: Bool?
    let accountID: String?
    let lastActivity: Date?
    let lastReadMessageSortKey: String?

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

    var allowsUnlimitedMessageEdits: Bool {
        accountID?.localizedStandardContains("telegram") == true
    }

    func participant(with id: String) -> ChatParticipant? {
        participants?.items.first(where: { $0.id == id })
    }

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
