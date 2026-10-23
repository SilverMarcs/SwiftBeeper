import Foundation

struct Reaction: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let reactionKey: String
    let participantID: String
}

struct Message: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let chatID: String
    let senderID: String
    let senderName: String?
    let timestamp: Date
    let sortKey: String
    let text: String?
    let isSender: Bool
    let attachments: [Attachment]?
    let isUnread: Bool?
    let reactions: [Reaction]?
    let linkedMessageID: String?
    /// True when the server has redacted this message. Its original content may
    /// still be present when the server observed it before the redaction.
    let isDeleted: Bool?
    /// Local transaction identifier attached to realtime events.
    /// History pages may omit it.
    let transactionID: String?

    /// Numeric sort key for correct ordering (handles negative backfill IDs).
    var numericSortKey: Int64 { Int64(sortKey) ?? 0 }

    var senderDisplayName: String {
        if let senderName, senderName.isEmpty == false {
            return senderName
        }
        return senderID
    }

    var displayText: String {
        if let visibleText {
            return visibleText
        }

        if let attachments, let first = attachments.first {
            return "Sent \(attachments.count > 1 ? "\(attachments.count) attachments" : "an \(first.typeLabel)")"
        }

        return "Deleted message"
    }

    /// Redacted, or with nothing left to show (an empty body and no attachments).
    var isDeletedMessage: Bool {
        isDeleted == true || (!hasText && (attachments ?? []).isEmpty)
    }

    var hasRetainedDeletedContent: Bool {
        isDeleted == true && (hasText || (attachments ?? []).isEmpty == false)
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
