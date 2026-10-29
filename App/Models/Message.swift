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
    let formattedText: String?
    let mentions: MessageMentions?
    let isSender: Bool
    let attachments: [Attachment]?
    let isUnread: Bool?
    let reactions: [Reaction]?
    let linkedMessageID: String?
    /// True when the homeserver has redacted this message. Its original content
    /// may still be present when the core saw it before the redaction.
    let isDeleted: Bool?
    /// Local transaction identifier attached to realtime events.
    /// History pages may omit it.
    let transactionID: String?

    /// Numeric sort key for correct ordering (handles negative backfill IDs).
    var numericSortKey: Int64 { Int64(sortKey) ?? 0 }

    var senderDisplayName: String {
        if let senderName, !senderName.isEmpty { return senderName }
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
        isDeleted == true && (hasText || !(attachments ?? []).isEmpty)
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

        // Media messages carry the attachment filename as their body text.
        // Suppress it so we don't show a redundant text bubble (e.g. "image" or "IMG_2647.jpeg").
        let isFileNameFallback = attachments?.contains { attachment in
            guard let fileName = attachment.fileName?.trimmed, !fileName.isEmpty else { return false }
            return fileName.localizedStandardCompare(trimmed) == .orderedSame
        } ?? false
        return isFileNameFallback ? nil : trimmed
    }

    var hasText: Bool { visibleText != nil }

    /// Formatting is presentation only; previews and copying use the plain body.
    var displayFormattedText: String {
        if let formattedText, !formattedText.isEmpty { return formattedText }
        return displayText
    }

    /// Reply notification recipients can include people absent from the body.
    /// The mention label requires a visible user link after reply fallback removal.
    func explicitlyMentions(_ userID: String) -> Bool {
        guard mentions?.userIDs.contains(userID) == true,
              let formattedText else { return false }
        return formattedText.messageAttributed.runs.contains { run in
            guard let url = run.link else { return false }
            return MessageMentionLink(url)?.userID == userID
        }
    }

    var timestampText: String {
        let calendar = Calendar.app
        if calendar.component(.year, from: timestamp) == calendar.component(.year, from: .now) {
            return timestamp.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
        return timestamp.formatted(date: .abbreviated, time: .shortened)
    }

    /// Visible reactions grouped by key, in key order; nil when there are none.
    var groupedReactions: [GroupedReaction]? {
        // Custom emoji and GIF reactions have no image representation in Relay.
        // Keep their data, but don't render raw shortcodes or media URLs.
        let visibleReactions = reactions?.filter {
            !($0.reactionKey.hasPrefix(":") && $0.reactionKey.hasSuffix(":"))
                && !$0.reactionKey.hasPrefix("mxc://")
                && !$0.reactionKey.hasPrefix("https://")
                && !$0.reactionKey.hasPrefix("http://")
        } ?? []
        guard !visibleReactions.isEmpty else { return nil }
        return Dictionary(grouping: visibleReactions, by: \.reactionKey)
            .map { key, group in
                GroupedReaction(reactionKey: key, count: group.count, participantIDs: group.map(\.participantID))
            }
            .sorted { $0.reactionKey < $1.reactionKey }
    }
}

struct GroupedReaction: Identifiable {
    var id: String { reactionKey }
    let reactionKey: String
    let count: Int
    let participantIDs: [String]
}
