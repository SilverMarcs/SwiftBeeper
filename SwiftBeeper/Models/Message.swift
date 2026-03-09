import Foundation

enum MessageKind: RawRepresentable, Decodable, Equatable {
    case reaction
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "REACTION":
            self = .reaction
        default:
            self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .reaction:
            return "REACTION"
        case .unknown(let value):
            return value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = MessageKind(rawValue: try container.decode(String.self))
    }
}

struct Reaction: Codable, Identifiable, Hashable {
    let id: String
    let reactionKey: String
    let imgURL: String?
    let participantID: String
    let emoji: Bool?
}

struct Message: Identifiable, Decodable, Equatable {
    let id: String
    let chatID: String
    let senderID: String
    let senderName: String?
    let timestamp: Date
    let sortKey: String
    let type: MessageKind?
    let text: String?
    let isSender: Bool?
    let attachments: [Attachment]?
    let isUnread: Bool?
    let reactions: [Reaction]?
    let linkedMessageID: String?

    var timelineKey: String { sortKey }

    var isReaction: Bool { type == .reaction }

    var isMembershipEvent: Bool {
        guard let loweredText = text?.lowercased() else { return false }
        return loweredText.contains("joined the chat") || loweredText.contains("was invited to the chat")
    }

    var senderDisplayName: String {
        if let senderName, senderName.isEmpty == false {
            return senderName
        }
        return senderID
    }

    var displayText: String {
        if isReaction {
            let emoji = text?.trimmed ?? ""
            let name = senderDisplayName
            if emoji.isEmpty {
                return "Reacted to a message"
            }
            return "\(name) reacted \(emoji)"
        }

        let trimmedText = text?.trimmed
        if let trimmedText, trimmedText.isEmpty == false {
            return trimmedText
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
        text?.trimmed.isEmpty == false
    }

    var timestampText: String {
        timestamp.formatted(date: .abbreviated, time: .shortened)
    }
}
