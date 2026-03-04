import Foundation

struct ListChatsOutput: Decodable {
    let items: [Chat]
}

struct ListMessagesOutput: Decodable {
    let items: [Message]
}

struct Chat: Identifiable, Decodable {
    let id: String
    let title: String
    let unreadCount: Int
    let preview: Message?

    var displayTitle: String {
        title.isEmpty ? "Untitled Chat" : title
    }

    var previewText: String? {
        preview?.displayText
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
