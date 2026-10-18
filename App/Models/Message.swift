import Foundation


enum MessageKind: RawRepresentable, Codable, Equatable, Sendable {
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct Reaction: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let reactionKey: String
    let imgURL: String?
    let participantID: String
    let emoji: Bool?
}

struct Message: Identifiable, Codable, Equatable, Sendable {


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
    /// Mentioned participant IDs. A nil value represents legacy messages whose
    /// mentions must be inferred from their displayed text.
    let mentions: [String]?
    let reactions: [Reaction]?
    let linkedMessageID: String?
    /// True when the server has redacted this message. Its original content may
    /// still be present when the server observed it before the redaction.
    let isDeleted: Bool?
    /// Local transaction identifier attached to hydrated realtime events.
    /// REST history may omit it.
    let transactionID: String?

    var timelineKey: String { sortKey }

    /// Numeric sort key for correct ordering (handles negative backfill IDs).
    var numericSortKey: Int64 { Int64(sortKey) ?? 0 }

    var isReaction: Bool { type == .reaction }

    var isMembershipEvent: Bool {
        type == .memberJoin || type == .memberInvite
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

        if let visibleText {
            return visibleText
        }

        if let attachments, let first = attachments.first {
            return "Sent \(attachments.count > 1 ? "\(attachments.count) attachments" : "an \(first.typeLabel)")"
        }

        return "Deleted message"
    }

    private var isLegacyDeletedTombstone: Bool {
        !hasText && (attachments ?? []).isEmpty
    }

    /// Includes the empty tombstone emitted by older server versions.
    var isDeletedMessage: Bool {
        isDeleted == true || isLegacyDeletedTombstone
    }

    var hasRetainedDeletedContent: Bool {
        isDeleted == true && (hasText || (attachments ?? []).isEmpty == false)
    }

    /// Whether this message represents real user content (not a reaction or membership event).
    /// Deleted messages remain displayable with their retained content or a
    /// tombstone when the original content is unavailable.
    var isDisplayable: Bool {
        !isReaction && !isMembershipEvent
    }

    /// User-visible body text after suppressing Matrix's required media
    /// filename fallback. Media captions remain visible.
    var visibleText: String? {
        guard let trimmed = text?.trimmed, !trimmed.isEmpty else { return nil }
        guard trimmed.unicodeScalars.contains(where: { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && scalar.properties.generalCategory != .control
                && scalar.properties.generalCategory != .format
        }) else { return nil }

        // The API echoes the attachment filename as message text for media messages.
        // Suppress it so we don't show a redundant text bubble (e.g. "image" or "IMG_2647.jpeg").
        if let attachments, !attachments.isEmpty {
            if attachments.contains(where: { attachment in
                guard let fileName = attachment.fileName?.trimmed, !fileName.isEmpty else { return false }
                return fileName.localizedStandardCompare(trimmed) == .orderedSame
            }) {
                return nil
            }
        }

        return trimmed
    }

    var hasText: Bool { visibleText != nil }

    var timestampText: String {
        let calendar = Calendar.app
        if calendar.component(.year, from: timestamp) == calendar.component(.year, from: Date()) {
            return timestamp.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
        return timestamp.formatted(date: .abbreviated, time: .shortened)
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

    /// Merges a freshly-fetched copy (`detail`) into this one, preserving richer
    /// data (like reactions or attachments) if the new copy omitted them.
    func merging(detail: Message) -> Message {
        let mergedSenderName = (detail.senderName?.isEmpty == false) ? detail.senderName : (senderName?.isEmpty == false ? senderName : nil)
        let mergedReactions = detail.reactions ?? reactions
        let mergedAttachments = detail.attachments ?? attachments

        return Message(
            id: detail.id,
            chatID: detail.chatID,
            senderID: detail.senderID,
            senderName: mergedSenderName,
            timestamp: detail.timestamp,
            sortKey: detail.sortKey,
            type: detail.type ?? type,
            text: detail.text ?? text,
            isSender: detail.isSender ?? isSender,
            attachments: mergedAttachments,
            isUnread: detail.isUnread ?? isUnread,
            mentions: detail.mentions ?? mentions,
            reactions: mergedReactions,
            linkedMessageID: detail.linkedMessageID ?? linkedMessageID,
            isDeleted: detail.isDeleted ?? isDeleted,
            transactionID: detail.transactionID ?? transactionID
        )
    }
}
