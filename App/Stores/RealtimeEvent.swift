import Foundation

/// A change reported by the Matrix core's event stream.
enum RealtimeEvent {
    /// The stream (re)connected. After the first connection, events may have
    /// been missed, so the UI reloads from the local database.
    case connected(requiresResync: Bool)
    /// A sequence gap or an event without its payload means at least one change
    /// could not be applied, so the UI reloads from the local database.
    case resyncRequired
    case notificationPreferencesChanged
    case chatUpserted(Chat)
    case chatDeleted(chatID: String)
    case messagesUpserted(chatID: String, messages: [Message])
    case receiptUpdated(chatID: String, lastReadByOtherSortKey: String)
    case failed(String)
}
