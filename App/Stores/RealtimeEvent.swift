import Foundation

/// A change reported by the Matrix core's event stream.
enum RealtimeEvent {
    /// The stream (re)connected. After the first connection, events may have
    /// been missed, so the UI reloads from the local database.
    case connected(requiresResync: Bool)
    case disconnected
    /// A sequence gap or an event without its payload means at least one change
    /// could not be applied, so the UI reloads from the local database.
    case resyncRequired
    case notificationPreferencesChanged
    /// Sent on connecting and whenever it changes. It follows the changes from
    /// the sync it reports on.
    case syncStatusChanged(MatrixSyncStatus)
    case chatUpserted(Chat)
    case chatDeleted(chatID: String)
    case messagesUpserted(chatID: String, messages: [Message])
    case receiptUpdated(chatID: String, lastReadByOtherSortKey: String)
    case typingUpdated(chatID: String, participants: [ChatParticipant])
    case failed(String)
}

/// The fields every realtime event shares.
struct EventEnvelope: Decodable {
    let type: String
    let chatID: String?
    let entries: [[String: String]]?
    let seq: Int?
    /// The `sync.status` signal's status.
    let status: String?

    enum CodingKeys: String, CodingKey {
        case type, chatID, entries, seq, status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        chatID = try? container.decodeIfPresent(String.self, forKey: .chatID)
        seq = try? container.decodeIfPresent(Int.self, forKey: .seq)
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        // Message events carry non-string values in entries; only receipt
        // events read this field, so fall back to nil on a type mismatch.
        entries = try? container.decodeIfPresent([[String: String]].self, forKey: .entries)
    }
}

/// The decoded `entries` of a chat or message event.
struct EntriesPayload<Entry: Decodable>: Decodable {
    let entries: [Entry]?
}
