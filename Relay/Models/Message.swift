import Foundation


enum MessageKind: RawRepresentable, Decodable, Equatable {
    case reaction
    case memberJoin
    case memberInvite
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "REACTION":
            self = .reaction
        case "MEMBER_JOIN":
            self = .memberJoin
        case "MEMBER_INVITE":
            self = .memberInvite
        default:
            self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .reaction:
            return "REACTION"
        case .memberJoin:
            return "MEMBER_JOIN"
        case .memberInvite:
            return "MEMBER_INVITE"
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

    /// Numeric sort key for correct ordering (handles negative backfill IDs).
    var numericSortKey: Int64 { Int64(sortKey) ?? 0 }

    var isReaction: Bool { type == .reaction }

    var isMembershipEvent: Bool {
        if type == .memberJoin || type == .memberInvite {
            return true
        }
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

        if hasText {
            return text!.trimmed
        }

        if let attachments, let first = attachments.first {
            return "Sent \(attachments.count > 1 ? "\(attachments.count) attachments" : "an \(first.typeLabel)")"
        }

        return "Deleted message"
    }

    var isEmptyDeleted: Bool {
        !hasText && (attachments ?? []).isEmpty
    }

    /// Whether this message represents real user content (not a reaction, membership event, or empty/deleted message).
    var isDisplayable: Bool {
        !isReaction && !isMembershipEvent && !isEmptyDeleted
    }

    var hasText: Bool {
        guard let trimmed = text?.trimmed, !trimmed.isEmpty else { return false }
        // The API echoes the attachment filename as message text for media messages.
        // Suppress it so we don't show a redundant text bubble (e.g. "image" or "IMG_2647.jpeg").
        if let attachments, !attachments.isEmpty {
            if attachments.contains(where: { $0.fileName == trimmed }) { return false }
        }
        return true
    }

    var extractedURLs: [URL]? {
        let urls = text?.extractedURLs ?? []
        return urls.isEmpty ? nil : urls
    }

    var textWithoutURLs: String? {
        guard let text = text?.trimmed, !text.isEmpty else { return nil }
        guard let urls = extractedURLs else { return text }
        var result = text
        for url in urls {
            result = result.replacingOccurrences(of: url.absoluteString, with: "")
        }
        let trimmed = result.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }

    var timestampText: String {
        timestamp.formatted(date: .abbreviated, time: .shortened)
    }

    func isOutgoing(in chat: Chat) -> Bool {
        if let isSender {
            return isSender
        }
        guard let currentParticipantID = chat.participants?.items.first(where: { $0.isSelf == true })?.id else {
            return false
        }
        return senderID == currentParticipantID
    }

    var groupedReactions: [GroupedReaction]? {
        guard let reactions, !reactions.isEmpty else {
            return nil
        }

        var groups: [String: GroupedReaction] = [:]
        for reaction in reactions {
            if var existing = groups[reaction.reactionKey] {
                existing.count += 1
                existing.participantIDs.append(reaction.participantID)
                groups[reaction.reactionKey] = existing
            } else {
                groups[reaction.reactionKey] = GroupedReaction(
                    reactionKey: reaction.reactionKey,
                    count: 1,
                    participantIDs: [reaction.participantID]
                )
            }
        }

        return groups.values.sorted(by: { $0.reactionKey < $1.reactionKey })
    }
}
