import Foundation
import OSLog

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
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SwiftBeeper", category: "Message")

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
        let matchedByText = loweredText.contains("joined the chat") || loweredText.contains("was invited to the chat")
        if matchedByText {
            Self.logger.info("isMembershipEvent matched by text fallback. type=\(String(describing: type), privacy: .public), text=\(loweredText, privacy: .public)")
        }
        return matchedByText
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

    /// Whether this message represents real user content (not a reaction, membership event, or empty/deleted message).
    var isDisplayable: Bool {
        !isReaction && !isMembershipEvent && !isEmptyDeleted
    }

    var hasText: Bool {
        text?.trimmed.isEmpty == false
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
