import Foundation

struct ListChatsOutput: Decodable {
    let items: [Chat]
}

struct ListMessagesOutput: Decodable {
    let items: [Message]
}

struct SendMessageOutput: Decodable {
    let chatID: String
    let pendingMessageID: String
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
        return "(No text)"
    }

    var timestampText: String {
        timestamp.formatted(date: .abbreviated, time: .shortened)
    }
}
