import Foundation

struct ChatParticipant: Identifiable, Codable, Equatable, Sendable {
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

struct ChatParticipants: Codable, Equatable, Sendable {
    let items: [ChatParticipant]
    let hasMore: Bool?
    let total: Int?
}

enum ChatKind: RawRepresentable, Codable, Equatable, Sendable {
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct Chat: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var title: String
    var unreadCount: Int
    var participants: ChatParticipants?
    var preview: Message?
    var isMuted: Bool?
    var type: ChatKind?
    var isArchived: Bool?
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
